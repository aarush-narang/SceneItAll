# Interior Design LiDAR

An iOS app that scans a room with Apple RoomPlan, renders it in RealityKit, and uses a Gemini-powered agent to suggest and place IKEA furniture. Retrieval is driven by CLIP image/text embeddings stored in MongoDB Atlas Vector Search.

## Stack

| Layer | Technology |
|---|---|
| iOS | Swift / SwiftUI, Apple RoomPlan, RealityKit, SwiftData |
| Backend | Python 3.11+, FastAPI, Motor (async MongoDB), Pydantic v2, structlog |
| Storage | MongoDB Atlas + Vector Search, AWS S3 (USDZ assets) |
| ML | OpenCLIP ViT-B/32 (512-d embeddings), Blender headless (4-angle renders) |
| Agent | Google Gemini with function calling |

## Repository structure

```
LAHacks2026/
  backend/                      # Python FastAPI backend
    app/
      app.py                    # FastAPI app factory + router includes
      config.py                 # pydantic-settings env loader
      db.py                     # Motor client + collection accessors
      logging.py                # structlog config
      models/                   # Pydantic v2 models (furniture, design, preferences, agent)
      routers/                  # One router per resource
      pipeline/                 # Matching, filtering, decision logic
      services/
        embeddings.py           # CLIP image + text encoders
        storage.py              # S3 upload/download
    scripts/
      create_db.py              # Create collections, field indexes, seed preference templates
      create_indexes.py         # Create Atlas Vector Search indexes
    eval/                       # Offline evaluation harness
    tests/                      # pytest suite
    start_server.sh             # Start uvicorn locally
    start_tunnel.sh             # Start uvicorn + ngrok tunnel (for iOS dev)
    requirements.txt
  FurnitureRoomPlacement/       # iOS Xcode project
    FurnitureRoomPlacement/
      HelperMethods/
        Consts.swift            # baseURL and shared data models — set your tunnel URL here
      ViewModels/               # SwiftUI view models
      Components/               # Reusable UI components
      ScanUpload/               # RoomPlan capture + upload logic
      ContentView.swift
      RoomCaptureContainerView.swift
      ScanMatchingView.swift
      FurnitureSearchView.swift
      DesignsListView.swift
      RoomEditorView.swift
      StyleQuizView.swift
```

---

## Backend setup

### Prerequisites

- Python 3.11+
- [conda](https://docs.conda.io/en/latest/) or any Python env manager
- [MongoDB Atlas](https://www.mongodb.com/atlas) cluster with Vector Search enabled (M10+ tier required for vector indexes)
- AWS S3 bucket for USDZ asset storage
- Google Gemini API key
- Blender (for furniture ingestion; `blender` must be on your PATH or set `BLENDER_PATH`)
- [ngrok](https://ngrok.com/) (for tunneling to the iOS app during local development)

### 1. Create the Python environment

```bash
conda create -n interior-design python=3.11 -y
conda activate interior-design
pip install -r backend/requirements.txt
```

### 2. Configure environment variables

```bash
cp backend/.env.example backend/.env
```

Fill in `backend/.env`:

| Variable | Description |
|---|---|
| `MONGODB_URI` | Atlas connection string (`mongodb+srv://user:pass@cluster.mongodb.net/`) |
| `MONGODB_DB` | Database name — use `interior_design` |
| `GEMINI_API_KEY` | Google Gemini API key |
| `AWS_ACCESS_KEY_ID` | AWS credentials for S3 |
| `AWS_SECRET_ACCESS_KEY` | AWS credentials for S3 |
| `AWS_REGION` | S3 region (e.g. `us-east-1`) |
| `S3_BUCKET` | S3 bucket name for USDZ + thumbnail assets |
| `BLENDER_PATH` | Path to Blender binary (default: `blender`) |

### 3. Database setup (run once)

```bash
# Create collections, field indexes, and seed preference templates
python backend/scripts/create_db.py

# Create Atlas Vector Search indexes (Atlas takes ~1 min to make them READY)
python backend/scripts/create_indexes.py
```

### 4. Start the backend

```bash
cd backend && ./start_server.sh
# or directly:
uvicorn app.app:app --reload --host 0.0.0.0 --port 8000
```

API available at `http://localhost:8000`. Interactive docs at `http://localhost:8000/docs`.

```bash
curl http://localhost:8000/health
# {"api": "ok", "db": "ok"}
```

---

## Connecting the iOS app to the backend

The iOS app must reach the backend over HTTPS. There are two options:

### Option A — ngrok tunnel (local development)

The easiest option for running locally alongside an iPhone or simulator.

```bash
cd backend && ./start_tunnel.sh
```

This starts both uvicorn and an ngrok tunnel. Copy the `https://....ngrok-free.app` URL printed by ngrok, then paste it into `FurnitureRoomPlacement/FurnitureRoomPlacement/HelperMethods/Consts.swift`:

```swift
let baseURL = "https://<your-ngrok-subdomain>.ngrok-free.app"
```

Rebuild and run the Xcode project. The tunnel URL changes each time you restart ngrok (unless you have a paid ngrok account with a reserved domain).

### Option B — hosted backend

Deploy the backend to any cloud provider (e.g. Railway, Render, Fly.io, AWS EC2). Set the public HTTPS URL in `Consts.swift` the same way. No tunnel needed.

---

## iOS app setup

Requirements:
- Xcode 15+
- iPhone with LiDAR sensor (iPhone 12 Pro or later) — RoomPlan does not work in the simulator
- iOS 17+

Open `FurnitureRoomPlacement/FurnitureRoomPlacement.xcodeproj` in Xcode, select your device, and run. Make sure `baseURL` in `Consts.swift` points to a reachable backend before building.

---

## API reference

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
| `POST` | `/scans` | Upload a room scan |

Full request/response schemas: `http://localhost:8000/docs`

---

## Running tests

```bash
cd backend
pytest tests/
```
