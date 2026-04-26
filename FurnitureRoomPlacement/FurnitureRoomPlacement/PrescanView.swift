import SwiftUI
import SceneKit
import UniformTypeIdentifiers

// MARK: - File Document for JSON Export

struct JSONExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Unsupported Device View

struct UnsupportedDeviceView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("RoomPlan is unavailable on this device.")
                .font(.title3.weight(.semibold))

            Text("Run the app on a LiDAR-enabled iPhone or iPad to capture a room.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

// MARK: - Imported Room Scene View (UIViewRepresentable)

struct ImportedRoomSceneView: UIViewRepresentable {
    let scene: SCNScene
    let interactionMode: FurnitureInteractionMode

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView(frame: .zero)
        scnView.scene = scene
        scnView.backgroundColor = UIColor(white: 0.72, alpha: 1.0)
        scnView.autoenablesDefaultLighting = true
        scnView.allowsCameraControl = interactionMode == .view
        scnView.defaultCameraController.interactionMode = .orbitTurntable
        scnView.isPlaying = true

        let panGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePanGesture(_:))
        )
        panGesture.maximumNumberOfTouches = 1
        scnView.addGestureRecognizer(panGesture)

        let rotationGesture = UIRotationGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleRotationGesture(_:))
        )
        scnView.addGestureRecognizer(rotationGesture)

        context.coordinator.panGestureRecognizer = panGesture
        context.coordinator.rotationGestureRecognizer = rotationGesture
        context.coordinator.sceneView = scnView
        context.coordinator.interactionMode = interactionMode
        panGesture.delegate = context.coordinator
        rotationGesture.delegate = context.coordinator

        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        scnView.scene = scene
        scnView.allowsCameraControl = interactionMode == .view
        context.coordinator.sceneView = scnView
        context.coordinator.interactionMode = interactionMode
        context.coordinator.panGestureRecognizer?.isEnabled = interactionMode != .view
        context.coordinator.rotationGestureRecognizer?.isEnabled = interactionMode != .view

        if interactionMode == .view {
            context.coordinator.cancelDragging()
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var sceneView: SCNView?
        weak var draggedNode: SCNNode?
        weak var panGestureRecognizer: UIPanGestureRecognizer?
        weak var rotationGestureRecognizer: UIRotationGestureRecognizer?
        var interactionMode: FurnitureInteractionMode = .view
        var movementPlaneY: Float = 0

        @objc func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
            guard interactionMode != .view, let sceneView else {
                cancelDragging()
                return
            }
            let location = gesture.location(in: sceneView)
            switch gesture.state {
            case .began: beginDragging(at: location, in: sceneView)
            case .changed: updateDragging(at: location, in: sceneView)
            case .ended, .cancelled, .failed: cancelDragging()
            default: break
            }
        }

        @objc func handleRotationGesture(_ gesture: UIRotationGestureRecognizer) {
            guard interactionMode == .move, let sceneView else {
                cancelDragging()
                return
            }
            let location = gesture.location(in: sceneView)
            switch gesture.state {
            case .began: beginDragging(at: location, in: sceneView)
            case .changed:
                updateRotation(with: gesture.rotation)
                gesture.rotation = 0
            case .ended, .cancelled, .failed: cancelDragging()
            default: break
            }
        }

        func cancelDragging() {
            draggedNode = nil
        }

        private func beginDragging(at location: CGPoint, in sceneView: SCNView) {
            for result in sceneView.hitTest(location, options: nil) {
                if let overlayNode = overlayAncestor(for: result.node) {
                    draggedNode = overlayNode
                    movementPlaneY = overlayNode.presentation.worldPosition.y
                    return
                }
            }
            draggedNode = nil
        }

        private func updateDragging(at location: CGPoint, in sceneView: SCNView) {
            guard let draggedNode,
                  let intersection = worldPointOnPlane(for: location, in: sceneView, planeY: movementPlaneY) else { return }
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0
            draggedNode.worldPosition = SCNVector3(intersection.x, movementPlaneY, intersection.z)
            SCNTransaction.commit()
        }

        private func updateRotation(with rotation: CGFloat) {
            guard let draggedNode else { return }
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0
            draggedNode.eulerAngles.y -= Float(rotation)
            SCNTransaction.commit()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { false }

        private func overlayAncestor(for node: SCNNode) -> SCNNode? {
            var current: SCNNode? = node
            while let candidate = current {
                if candidate.name?.hasPrefix("external-usdz-overlay") == true { return candidate }
                current = candidate.parent
            }
            return nil
        }

        private func worldPointOnPlane(for location: CGPoint, in sceneView: SCNView, planeY: Float) -> SCNVector3? {
            let near = sceneView.unprojectPoint(SCNVector3(Float(location.x), Float(location.y), 0))
            let far = sceneView.unprojectPoint(SCNVector3(Float(location.x), Float(location.y), 1))
            let dir = far - near
            guard abs(dir.y) > 0.0001 else { return nil }
            let t = (planeY - near.y) / dir.y
            guard t.isFinite else { return nil }
            return near + (dir * t)
        }
    }
}

// MARK: - SCNVector3 Arithmetic

func +(lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
    SCNVector3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
}

func -(lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
    SCNVector3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
}

func *(vector: SCNVector3, scalar: Float) -> SCNVector3 {
    SCNVector3(vector.x * scalar, vector.y * scalar, vector.z * scalar)
}

// MARK: - SCNScene Identifiable

extension SCNScene: @retroactive Identifiable {
    public var id: ObjectIdentifier {
        ObjectIdentifier(self)
    }
}
