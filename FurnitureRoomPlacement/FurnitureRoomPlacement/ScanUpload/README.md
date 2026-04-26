# ScanUpload

Frontend half of the scan-to-catalog matching pipeline.

## Files

| File | Purpose |
| --- | --- |
| `FrameSampler.swift` | `ARSessionDelegate` that captures throttled JPEG frames + camera pose/intrinsics during a RoomPlan scan |
| `ScanPayloadBuilder.swift` | Turns a `CapturedRoom` + frames into the JSON the backend expects |
| `MultipartFormBuilder.swift` | Tiny utility for building `multipart/form-data` bodies |
| `ScanUploadClient.swift` | `async` upload to `POST /v1/scans` and decode the response |
| `MatchedScene.swift` | Codable types for the backend's `ScanResponse` |

## Adding to Xcode

The files live under `FurnitureRoomPlacement/FurnitureRoomPlacement/ScanUpload/`
but are not yet added to the Xcode project. To add them:

1. In Xcode, right-click the `FurnitureRoomPlacement` group in the Project
   Navigator → **Add Files to "FurnitureRoomPlacement"…**
2. Select the `ScanUpload` folder; check **Create groups** (not folder
   references) and confirm the `FurnitureRoomPlacement` target is checked.
3. Build. There are no extra dependencies — everything uses RoomPlan, ARKit,
   CoreImage, and Foundation, which are already linked.

## Wiring into `RoomCaptureModel`

`FrameSampler` needs to be installed on the underlying `ARSession` *before* the
RoomPlan scan begins. In `RoomCaptureContainerView.swift`:

```swift
@MainActor
final class RoomCaptureModel: ObservableObject {
    // existing state...
    let frameSampler = FrameSampler()
    private let uploadClient = try! ScanUploadClient(baseURLString: "http://YOUR_BACKEND_HOST:8000")

    func startSession() {
        guard let roomCaptureView, !isScanning else { return }
        finalResults = nil
        canExport = false
        isProcessing = false
        isScanning = true

        roomCaptureView.captureSession.run(configuration: roomCaptureSessionConfig)

        // Hook into RoomPlan's underlying ARSession to sample frames.
        // (`RoomCaptureSession.arSession` is iOS 17+.)
        if #available(iOS 17.0, *) {
            roomCaptureView.captureSession.arSession.delegate = frameSampler
        }
    }

    func handleProcessedResult(_ processedResult: CapturedRoom) {
        finalResults = processedResult
        canExport = true
        isProcessing = false
    }

    func uploadAndMatch() async {
        guard let finalResults else { return }
        isProcessing = true
        defer { isProcessing = false }

        let frames = frameSampler.snapshot()
        do {
            let scene = try await uploadClient.upload(room: finalResults, frames: frames)
            // Hand `scene.objects` to the existing scene builder. For each match
            // download `matchedUSDZURL` and place at `transform`. Where
            // `matchedProductId == nil`, render a wireframe white-box at the
            // same `transform` (see "White-box rendering" below).
            handleMatchedScene(scene)
        } catch {
            errorMessage = error.localizedDescription
            isShowingError = true
        }
    }
}
```

Replace `YOUR_BACKEND_HOST` with the device-reachable address of the FastAPI
host. For dev builds, that's likely your Mac's LAN IP (e.g. `192.168.x.y:8000`).

## White-box rendering

When `MatchedObject.matchedProductId == nil`, render a placeholder wireframe
box of the detected dimensions at `MatchedObject.transform`, with
`refinedCategory` floating above it as a label. This gives users immediate
visual feedback that "we know there's a sofa here, but couldn't find an IKEA
match." Reuse `BarebonesRoomSceneBuilder`'s outline-edge approach (see the
private `makeOutlineNode(from:kind:)` helpers) — that's the same dashed-edge
look already used for room surfaces.

## Coordinate conventions (must match the backend)

| Field | Convention |
| --- | --- |
| `DetectedObject.transform` | 16-float column-major (`simd_float4x4` flattened by columns) |
| `FrameMetadata.camera_transform` | row-major nested 4x4 (list of rows) |
| `FrameMetadata.camera_intrinsics` | row-major nested 3x3 |

`ScanPayloadBuilder` handles all of these correctly — don't roll your own
conversions.

## Testing

There's no unit test target for ScanUpload yet. Easiest manual verification:

1. Run the FastAPI backend locally (`uvicorn app.main:app --reload`).
2. Build & run the iOS app on a device on the same Wi-Fi as the backend.
3. Set `baseURLString` to your Mac's LAN IP.
4. Scan a room → tap your "upload" button → watch the backend logs for
   `scan.received` and `scan.complete` lines.
