# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

LiDAR-based iOS app: the user scans a room with Apple RoomPlan, the room renders in RealityKit, and a Gemini-powered agent suggests and places furniture from an IKEA-based catalog. Retrieval is driven by CLIP image/text embeddings stored in MongoDB Atlas Vector Search.

**Stack**

- iOS: Swift / SwiftUI, Apple RoomPlan, RealityKit, SwiftData for the saved-projects list.
- Backend: Python 3.11+, FastAPI + uvicorn, `motor` (async MongoDB), pydantic v2, structlog, python-dotenv.
- Storage: MongoDB Atlas (+ Vector Search), S3 via boto3 for USDZ assets.
- ML: `open_clip_torch` (ViT-B/32 image + text encoders, 512-d); Blender headless via `subprocess` for 4-angle renders.
- Agent: `google-genai` with function calling.

## Repo state

The two Python files currently in this repo (`insert_data.py`, `vector_search.py`) are throwaway smoke tests against MongoDB Atlas Vector Search using a movie-plot dataset and OpenAI embeddings. **They are not product code and should not be extended.** Treat them as proof that the Atlas + pymongo wiring works; everything under _Backend architecture_ below still needs to be built fresh.

## Backend architecture plan

Target layout under `backend/`:

```
backend/
  app/
    main.py              # FastAPI app factory + router includes
    config.py            # pydantic-settings (env loader)
    db.py                # motor client + collection accessors
    logging.py           # structlog config
    models/              # pydantic v2 models, one file per domain
      furniture.py
      design.py
      preferences.py
      agent.py
    routers/             # one file per resource
      furniture.py
      designs.py
      preferences.py
      agent.py
    services/
      embeddings.py      # CLIP image + text encoders
      render.py          # Blender headless wrapper
      storage.py         # boto3 S3 bucket
      gemini.py          # agent loop + tool dispatcher
      preference_extractor.py
  scripts/
    ingest_ikea.py       # pull items → render → embed → insert
    create_indexes.py    # create Atlas vector search indexes
    create_db.py         # create the interior_design database + all collections with field indexes
```

### Routes

| Method | Path                                               | Purpose                                                                                            |
| ------ | -------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| GET    | `/furniture/search?q=&category=&max_price=&limit=` | Text → CLIP text embedding → `$vectorSearch` on `text_embedding`.                                  |
| GET    | `/furniture/similar?id=&max_price=&limit=`         | k-NN on `visual_embedding` of the given item (exclude self).                                       |
| GET    | `/furniture/{id}`                                  | Fetch one catalog item (used by agent + iOS detail).                                               |
| GET    | `/designs?user_id=`                                | List designs.                                                                                      |
| POST   | `/designs`                                         | Create design from uploaded CapturedRoom USDZ + RoomPlan JSON metadata.                            |
| GET    | `/designs/{id}`                                    | Room shell + placed items.                                                                         |
| PATCH  | `/designs/{id}`                                    | Partial update: rename, add/move/delete placed items.                                              |
| DELETE | `/designs/{id}`                                    | Soft-delete.                                                                                       |
| GET    | `/preferences/{user_id}`                           | Active PreferenceProfile for a user.                                                               |
| PUT    | `/preferences/{user_id}`                           | Replace profile (import/export).                                                                   |
| POST   | `/preferences/extract`                             | Derive style_tags, color_palette, etc. from a completed design (milestone 3.3, on the cut list).   |
| POST   | `/agent/chat`                                      | Gemini chat turn w/ tool calling → assistant text + placement suggestions with per-item rationale. |

All request/response bodies use pydantic models from `app/models/`. Every mutating endpoint validates both catalog existence and room-bounds containment before writing.

## MongoDB collections & pydantic models

Collections below are schemaless at the driver level — these pydantic models are the source of truth; create Atlas collections named to match.

### `furniture`

```python
class Dimensions(BaseModel):
    width_m: float   # x
    height_m: float  # y
    depth_m: float   # z

class FurnitureItem(BaseModel):
    id: str                        # stable SKU-like id, used as _id
    source: Literal["ikea"]
    source_url: HttpUrl            # for the shopping list view
    name: str
    description: str               # CLIP text-encoder input
    category: str                  # "sofa" | "chair" | "table" | "bed" | ...
    price_usd: float
    dimensions: Dimensions
    usdz_url: HttpUrl              # S3
    thumbnail_url: HttpUrl
    visual_embedding: list[float]  # mean of 4 CLIP image embeddings (512-d, ViT-B/32)
    text_embedding: list[float]    # CLIP text encoder(description), 512-d
    dimension_vector: list[float]  # normalized [w, h, d]
    color_tags: list[str] = []
    material_tags: list[str] = []
    style_tags: list[str] = []
    created_at: datetime
```

Atlas vector search indexes (create via `scripts/create_indexes.py`):

- `visual_index` on `visual_embedding` — 512 dims, cosine.
- `text_index` on `text_embedding` — 512 dims, cosine.

### `designs`

```python
class Vec3(BaseModel):
    x: float; y: float; z: float

class Quat(BaseModel):
    x: float; y: float; z: float; w: float

class PlacedItem(BaseModel):
    instance_id: str               # UUID — allows duplicates of the same SKU
    item_id: str                   # → FurnitureItem.id
    position: Vec3                 # meters, room-local
    rotation: Quat
    placed_by: Literal["user", "agent"] = "user"
    rationale: str | None = None   # populated when placed_by == "agent"

class RoomShell(BaseModel):
    usdz_url: HttpUrl              # CapturedRoom export from RoomPlan
    metadata_json_url: HttpUrl     # RoomPlan JSON (walls, floor, ceiling, doors, windows)
    floor_polygon: list[Vec3]      # 2D footprint at y=0; used for place_item bounds checks
    bbox_min: Vec3
    bbox_max: Vec3

class Design(BaseModel):
    id: str                        # UUID
    user_id: str
    name: str
    preference_profile_id: str | None
    shell: RoomShell
    placed_items: list[PlacedItem] = []
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None = None
```

`floor_polygon` and `bbox` are derived from the uploaded RoomPlan JSON on `POST /designs` and must be present before any `place_item` call can be validated.

### `preferences`

```python
class PreferenceProfile(BaseModel):
    id: str
    user_id: str | None                       # null on seed templates
    is_template: bool = False                 # true for the 3 demo seeds
    template_name: str | None                 # "minimalist" | "cozy" | "midcentury"
    style_tags: list[str]
    color_palette: list[str]                  # hex codes
    material_preferences: list[str]
    spatial_density: Literal["sparse", "balanced", "dense"]
    category_preferences: dict[str, float]    # category → weight in [0, 1]
    philosophies: list[str]                   # short sentences fed into Gemini's system prompt
    hard_requirements: dict[str, Any]         # e.g. {"max_price_per_item": 500, "avoid_categories": ["leather"]}
    taste_vector: list[float] | None = None   # derived: weighted mean of liked items' visual_embedding
    created_at: datetime
    updated_at: datetime
```

Seed the three templates (`minimalist`, `cozy`, `midcentury`) with `is_template=True` and `user_id=None`; on first launch the iOS app clones the chosen template into a user-scoped row.

### `chat_sessions` (optional)

Only needed once multi-turn memory matters; single-turn `/agent/chat` can run stateless.

```python
class ChatTurn(BaseModel):
    role: Literal["user", "assistant", "tool"]
    content: str
    tool_name: str | None = None
    tool_args: dict | None = None
    tool_result: dict | None = None
    ts: datetime

class ChatSession(BaseModel):
    id: str
    user_id: str
    design_id: str
    turns: list[ChatTurn]
    created_at: datetime
```

## Gemini agent contract

`POST /agent/chat` runs a tool-calling loop. Tools exposed to Gemini:

- `search_furniture(query: str, filters: {category?, max_price?, style_tags?})` → list of FurnitureItem summaries (strip embeddings from the response).
- `get_room_state(design_id)` → `{shell.bbox, placed_items}` (also strip embeddings).
- `place_item(design_id, item_id, position: Vec3, rotation: Quat)` — **server-side validation before persist**: item_id exists, `position` is inside `shell.floor_polygon`, placed bounding box fits under `shell.bbox_max.y`, no hard-requirement violation.
- `get_preferences(user_id)` → PreferenceProfile.
- `suggest_alternatives(item_id, max_price?)` → k-NN on `visual_embedding` with price filter.

Every tool call is validated against pydantic schemas before it mutates state; on failure, feed the structured error back to the model so it can retry rather than proposing the same invalid placement. Each agent-placed item carries a one-sentence `rationale` in the response.

**Invariant from the README's ordering: validate Gemini tool-calling end-to-end _before_ building any agent UI.** If the model hallucinates coordinates or nonexistent item IDs, fix that before shipping the chat sheet.

## iOS plan (backend-facing context)

- `Designs` home lists SwiftData-backed projects; `+` launches `RoomCaptureView`.
- On capture complete, upload USDZ + JSON metadata → `POST /designs`.
- Detail view renders `RoomShell` in RealityKit. Tap-to-select on RoomPlan furniture anchors opens a Move / Delete / Replace sheet.
- Furniture search UI hits `GET /furniture/search`; selecting downloads USDZ and drops it at the crosshair → `PATCH /designs/{id}`.
- "Ask Agent" chat sheet → `POST /agent/chat`. "Accept all" applies every returned placement in one PATCH.
- "Strip Room" clears `placed_items` but preserves `shell`.

## Environment

Copy `.env.example` → `.env`. Existing keys:

- `MONGODB_URI` — Atlas connection string.
- `MONGODB_INDEX_NAME` — used only by the stub scripts. The real backend will reference distinct indexes (`visual_index`, `text_index`) by name directly.
- `OPENAI_API_KEY` — **stub scripts only**; product code uses local CLIP, not OpenAI embeddings.

Additional keys the backend will need once built: `GEMINI_API_KEY`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `S3_BUCKET`, `BLENDER_PATH`.

## Commands

```bash
# Create and activate conda environment (Python 3.11)
conda create -n interior-design python=3.11 -y
conda activate interior-design
pip install -r requirements.txt

# Stub scripts (throwaway — only for sanity-checking Atlas Vector Search wiring)
python insert_data.py       # seeds test_data.test with movies
python vector_search.py     # REPL querying the vector_index

# Database setup (run once after filling in .env)
python backend/scripts/create_db.py
python backend/scripts/create_indexes.py   # Atlas takes ~1 min to make indexes READY

# Backend
uvicorn app.main:app --reload
```

No test suite, linter, or CI is configured yet. `requirements.txt` lists all deps for both stub scripts and the backend.
