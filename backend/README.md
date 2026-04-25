# Interior Design LiDAR

An iOS app that scans a room with Apple RoomPlan, renders it in RealityKit, and uses a Gemini-powered agent to suggest and place furniture from an IKEA-based catalog. Retrieval is driven by CLIP image/text embeddings stored in MongoDB Atlas Vector Search.

**Stack**

- iOS: Swift / SwiftUI, Apple RoomPlan, RealityKit, SwiftData
- Backend: Python 3.11+, FastAPI, Motor (async MongoDB), Pydantic v2, structlog
- Storage: MongoDB Atlas + Vector Search, S3 (USDZ assets)
- ML: OpenCLIP ViT-B/32 (512-d image + text embeddings), Blender headless for 4-angle renders
- Agent: Google Gemini with function calling

---

## Prerequisites

- Python 3.11+
- [conda](https://docs.conda.io/en/latest/) (recommended) or any Python env manager
- [MongoDB Atlas](https://www.mongodb.com/atlas) cluster with Vector Search enabled (M10+ tier required for vector indexes)
- AWS S3 bucket for USDZ asset storage
- Google Gemini API key
- Blender installed (for furniture ingestion; `blender` must be on your PATH or set `BLENDER_PATH`)

---

## Environment setup

**1. Clone and create the conda environment:**

```bash
conda create -n interior-design python=3.11 -y
conda activate interior-design
pip install -r requirements.txt
```

**2. Configure environment variables:**

```bash
cp .env.example .env
```

Fill in `.env`:

| Variable | Description |
|---|---|
| `MONGODB_URI` | Atlas connection string (e.g. `mongodb+srv://user:pass@cluster.mongodb.net/`) |
| `MONGODB_DB` | Database name — use `interior_design` |
| `GEMINI_API_KEY` | Google Gemini API key |
| `AWS_ACCESS_KEY_ID` | AWS credentials for S3 |
| `AWS_SECRET_ACCESS_KEY` | AWS credentials for S3 |
| `AWS_REGION` | S3 region (e.g. `us-east-1`) |
| `S3_BUCKET` | S3 bucket name for USDZ + thumbnail assets |
| `BLENDER_PATH` | Path to Blender binary (default: `blender`) |
| `OPENAI_API_KEY` | Only needed for the throwaway stub scripts, not the backend |

---

## Database setup (run once)

**1. Create collections and field indexes, and seed preference templates:**

```bash
python backend/scripts/create_db.py
```

This creates the `furniture`, `designs`, `preferences`, and `chat_sessions` collections with the appropriate indexes, and seeds three preference templates: `minimalist`, `cozy`, and `midcentury`.

**2. Create Atlas Vector Search indexes:**

```bash
python backend/scripts/create_indexes.py
```

This creates two vector indexes on the `furniture` collection:
- `text_index` — 512-d cosine index on `text_embedding` (used by `/furniture/search`)
- `visual_index` — 512-d cosine index on `visual_embedding` (used by `/furniture/similar`)

Atlas takes approximately 1 minute to bring new vector indexes to `READY` status. The backend will return errors on vector search routes until the indexes are ready.

---

## Ingesting the furniture catalog

Once the database and indexes are set up, ingest furniture items from a JSON catalog file:

```bash
python backend/scripts/ingest_ikea.py --catalog path/to/catalog.json
```

The catalog JSON must be a list of objects with the following fields:

```json
[
  {
    "id": "sofa-001",
    "source_url": "https://www.ikea.com/...",
    "name": "KIVIK Sofa",
    "description": "A comfortable 3-seat sofa with clean lines and firm cushions.",
    "category": "sofa",
    "price_usd": 799.0,
    "dimensions": { "width_m": 2.28, "height_m": 0.83, "depth_m": 0.95 },
    "usdz_local_path": "path/to/model.usdz",
    "thumbnail_local_path": "path/to/thumbnail.png",
    "color_tags": ["gray"],
    "material_tags": ["fabric"],
    "style_tags": ["modern"]
  }
]
```

The script will:
1. Render the USDZ from 4 angles using Blender
2. Compute CLIP visual and text embeddings
3. Upload the USDZ and thumbnail to S3
4. Insert the document into MongoDB

---

## Starting the backend

```bash
uvicorn app.main:app --reload --app-dir backend
```

The API will be available at `http://localhost:8000`. Interactive docs at `http://localhost:8000/docs`.

**Verify the server is healthy:**

```bash
curl http://localhost:8000/health
# {"api": "ok", "db": "ok"}
```

---

## API routes

| Method | Path | Description |
|---|---|---|
| `GET` | `/health` | Liveness + DB connectivity check |
| `GET` | `/furniture/search?q=&category=&max_price=&limit=` | Text → CLIP embedding → vector search |
| `GET` | `/furniture/similar?id=&max_price=&limit=` | Visual k-NN on a given item |
| `GET` | `/furniture/{id}` | Fetch a single catalog item |
| `GET` | `/designs?user_id=` | List designs for a user |
| `POST` | `/designs` | Create design from RoomPlan USDZ + JSON metadata |
| `GET` | `/designs/{id}` | Fetch room shell + placed items |
| `PATCH` | `/designs/{id}` | Rename, add/move/delete placed items |
| `DELETE` | `/designs/{id}` | Soft-delete a design |
| `GET` | `/preferences/{user_id}` | Get active preference profile |
| `PUT` | `/preferences/{user_id}` | Replace preference profile |
| `POST` | `/preferences/extract` | Derive style preferences from a completed design |
| `POST` | `/agent/chat` | Gemini chat turn with tool calling → placement suggestions |

Full request/response schemas are available in the interactive docs at `/docs`.

---

## Repository structure

```
backend/
  app/
    main.py              # FastAPI app factory + router includes
    config.py            # pydantic-settings env loader
    db.py                # Motor client + collection accessors
    logging.py           # structlog config
    models/              # Pydantic v2 models (furniture, design, preferences, agent)
    routers/             # One router per resource
    services/
      embeddings.py      # CLIP image + text encoders
      render.py          # Blender headless wrapper
      storage.py         # S3 upload/download
      gemini.py          # Gemini agent loop + tool dispatcher
      preference_extractor.py
  scripts/
    create_db.py         # Create collections + field indexes + seed preference templates
    create_indexes.py    # Create Atlas Vector Search indexes
    ingest_ikea.py       # Render → embed → upload → insert catalog items
```
