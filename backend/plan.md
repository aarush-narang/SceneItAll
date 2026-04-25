LiDAR based room design iOS app with an AI furniture recommender.

Stack: Swift and SwiftUI with Apple RoomPlan and RealityKit for iOS. Python with FastAPI for the backend. MongoDB Atlas with Vector Search for storage. Gemini API for the agent. CLIP for embeddings. IKEA USDZ files as the furniture catalog.

MILESTONE 1. Core iOS scan and render

1. Create a SwiftUI app with a Designs home screen that lists saved projects from SwiftData plus a plus button.
2. Integrate Apple RoomPlan. On plus tap, launch RoomCaptureView, guide the user through scanning, and save the CapturedRoom as USDZ plus a JSON metadata file.
3. Render saved rooms in a detail view using RealityKit. Enable tap to select on furniture anchors that RoomPlan identified.
4. For selected objects, show a bottom sheet with Move, Delete, and Replace actions.
5. Add a Strip Room button that removes every furniture anchor and keeps the shell.

MILESTONE 2. Backend scaffold and furniture catalog

1. Set up a FastAPI project with uvicorn, pydantic models, and motor (async MongoDB driver). Use python dotenv for config and structlog for logging.
2. Write a Python ingestion script that pulls IKEA items (name, dimensions, category, price, USDZ URL) and uploads USDZ files to object storage (S3 via boto3).
3. For each item, render 4 angles using Blender headless via subprocess. Pass renders through CLIP (open_clip_torch package) for a visual vector by averaging the 4 embeddings. Pass the description through the same CLIP text encoder for a text vector. Store both plus a normalized dimension vector in MongoDB Atlas.
4. Create vector search indexes in Atlas on visual_embedding and text_embedding.
5. Build these FastAPI endpoints.
   GET /furniture/search with query param q
   GET /furniture/similar with id and optional max_price
   GET /designs
   POST /designs
   PATCH /designs/id
   POST /agent/chat
6. Wire the iOS app to /furniture/search. Show results with thumbnails. Tapping a result downloads the USDZ and drops it into the scene at the crosshair.

MILESTONE 3. Design preference document

1. Define a PreferenceProfile pydantic schema with style_tags, color_palette, material_preferences, spatial_density, category_preferences, philosophies, hard_requirements, and taste_vector.
2. Seed 3 hardcoded preference profiles for the demo (minimalist, cozy, midcentury). Let users pick one on first launch.
3. Build a room extraction endpoint. Given a completed design, derive style_tags from placed furniture categories and colors server side and return an updated profile.
4. Add import and export so users can save a profile.json file and apply it to new designs. Expose GET and PUT /preferences/user_id.

MILESTONE 4. Gemini agent

1. Implement POST /agent/chat with the google generativeai Python SDK using function calling. Expose these tools to Gemini.
   search_furniture(query, filters)
   get_room_state(design_id)
   place_item(design_id, item_id, position, rotation)
   get_preferences(user_id)
   suggest_alternatives(item_id, max_price)
2. Validate every tool call server side against pydantic schemas before applying it. Reject invalid coordinates, nonexistent item ids, or placements outside room bounds.
3. Use few shot examples in the system prompt so Gemini returns valid placement JSON reliably.
4. Have the agent return a one sentence rationale per placed item. Return this in the response alongside the placement list.
5. In the iOS app, add an Ask Agent button that opens a chat sheet. User types a goal. The agent calls get_preferences, searches furniture, and returns placement suggestions with the rationale shown under each item. Accept all button applies every suggestion.

MILESTONE 5. Polish for demo

1. Before and after slider on the design view.
2. Shopping list view with IKEA links and total price.
3. Seed 3 pre made rooms so the demo still works if scanning fails on stage.
4. Record a fallback video of the full flow in case of network or sensor trouble.

Order of operations. Start with milestone 1 and milestone 2 in parallel if you have two people. Validate Gemini tool calling end to end on hour one of milestone 4 before building any UI for it. If the agent hallucinates coordinates or picks items that do not exist, fix that first.

Cut list if time runs short. Drop the room extraction path (milestone 3 step 3). Drop suggest_alternatives. Drop version control. Keep the scan, the search, the agent, and the shopping list.
