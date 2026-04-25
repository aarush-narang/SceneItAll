/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
SwiftUI onboarding and unsupported-device screens.
*/

import SwiftUI
import RoomPlan
import SceneKit
import UniformTypeIdentifiers
import UIKit

private enum FurnitureInteractionMode {
    case view
    case move
}

struct OnboardingView: View {
    private enum ImportMode {
        case barebones
        case stripFurniture
    }

    @State private var isShowingCaptureView = false
    @State private var isShowingUnsupportedDeviceSheet = false
    @State private var isShowingImporter = false
    @State private var importMode: ImportMode = .barebones
    @State private var importedScene: SCNScene?
    @State private var importedFileName = ""
    @State private var importErrorMessage = ""
    @State private var isShowingImportError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            Text("Create a 3D model of a room")
                .font(.largeTitle.weight(.bold))

            VStack(alignment: .leading, spacing: 12) {
                Label("Move slowly and keep walls, windows, and doors in view.", systemImage: "camera.viewfinder")
                Label("Walk the perimeter of the room before capturing details.", systemImage: "square.dashed")
                Label("Finish scanning when the room outline looks complete.", systemImage: "checkmark.circle")
            }
            .font(.headline)
            .foregroundStyle(.secondary)

            Spacer()

            VStack(spacing: 12) {
                Button("Start Scan") {
                    if RoomCaptureSession.isSupported {
                        isShowingCaptureView = true
                    } else {
                        isShowingUnsupportedDeviceSheet = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .center)

                Button("Import Barebones JSON") {
                    importMode = .barebones
                    isShowingImporter = true
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .center)

                Button("Import JSON & Strip Furnitures") {
                    importMode = .stripFurniture
                    isShowingImporter = true
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .fullScreenCover(isPresented: $isShowingCaptureView) {
            RoomCaptureContainerView()
        }
        .sheet(isPresented: $isShowingUnsupportedDeviceSheet) {
            NavigationStack {
                UnsupportedDeviceView()
                    .navigationTitle("Unavailable")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Close") {
                                isShowingUnsupportedDeviceSheet = false
                            }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
        .fullScreenCover(item: $importedScene) { scene in
            ImportedRoomShellView(scene: scene, title: importedFileName)
        }
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("Import Failed", isPresented: $isShowingImportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importErrorMessage)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let fileURL = try result.get().first else { return }
            let didAccess = fileURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: fileURL)
            let scene: SCNScene

            switch importMode {
            case .barebones:
                scene = try BarebonesRoomImportLoader.loadScene(from: data)
            case .stripFurniture:
                let strippedData = try BarebonesRoomJSONSanitizer.stripToEssentialSurfaces(from: data)
                scene = try BarebonesRoomImportLoader.loadScene(from: strippedData)
            }

            importedFileName = fileURL.deletingPathExtension().lastPathComponent
            importedScene = scene
        } catch {
            importErrorMessage = error.localizedDescription
            isShowingImportError = true
        }
    }
}

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

private struct ImportedRoomShellView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingOverlayError = false
    @State private var hasOverlayedExternalUSDZ = false
    @State private var areWallsDimmed = false
    @State private var showFurnitureCatalog: Bool = false
    @State private var furnitureInteractionMode: FurnitureInteractionMode = .view

    let scene: SCNScene
    let title: String

    var body: some View {
        NavigationStack {
            ImportedRoomSceneView(
                scene: scene,
                interactionMode: furnitureInteractionMode
            )
            .background(Color(white: 0.72))
            .ignoresSafeArea()
            .navigationTitle(title.isEmpty ? "Imported Room" : title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
//                    Button(hasOverlayedExternalUSDZ ? "USDZ Added" : "Overlay USDZ") {
//                        let didAddOverlay = BarebonesRoomSceneBuilder.overlayExternalUSDZ(on: scene)
//                        hasOverlayedExternalUSDZ = didAddOverlay || hasOverlayedExternalUSDZ
//                        isShowingOverlayError = !didAddOverlay
//                    }
//                    .disabled(hasOverlayedExternalUSDZ)
                    Button("Add Furniture") {
                        showFurnitureCatalog.toggle()
                    }

                    Button(
                        furnitureInteractionMode == .move ? "Done Moving" : "Move Furniture"
                    ) {
                        furnitureInteractionMode = furnitureInteractionMode == .move ? .view : .move
                    }
                    .disabled(!hasOverlayedExternalUSDZ)

                    Button(areWallsDimmed ? "Walls 100%" : "Walls 50%") {
                        areWallsDimmed.toggle()
                        updateWallOpacity(in: scene, opacity: areWallsDimmed ? 0.5 : 1.0)
                        updateShellDepth(in: scene, writesToDepthBuffer: !areWallsDimmed)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .alert("Unable to Overlay USDZ", isPresented: $isShowingOverlayError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("The app could not load the external USDZ asset.")
            }
            .onChange(of: hasOverlayedExternalUSDZ) { _, hasOverlay in
                if !hasOverlay {
                    furnitureInteractionMode = .view
                }
            }
            .sheet(isPresented: $showFurnitureCatalog) {
                NavigationStack {
                    FurnitureCatalogListView(
                        showFurnitureCatalog: $showFurnitureCatalog,
                        hasOverlayedExternalUSDZ: $hasOverlayedExternalUSDZ,
                        scene: scene
                    )
                }
                .presentationDetents([.fraction(0.92), .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private func updateWallOpacity(in scene: SCNScene, opacity: CGFloat) {
        let wallNodes = scene.rootNode.childNodes(passingTest: { node, _ in
            node.name?.hasPrefix("wall-") == true
        })

        for wallNode in wallNodes {
            updateOpacityRecursively(for: wallNode, opacity: opacity)
        }
    }

    private func updateShellDepth(in scene: SCNScene, writesToDepthBuffer: Bool) {
        let shellNodes = scene.rootNode.childNodes(passingTest: { node, _ in
            guard let name = node.name else {
                return false
            }

            return name.hasPrefix("wall-")
                || name.hasPrefix("door-")
                || name.hasPrefix("window-")
                || name.hasPrefix("opening-")
        })

        for shellNode in shellNodes {
            updateDepthRecursively(for: shellNode, writesToDepthBuffer: writesToDepthBuffer)
        }
    }

    private func updateOpacityRecursively(for node: SCNNode, opacity: CGFloat) {
        node.opacity = opacity

        if let geometry = node.geometry {
            for material in geometry.materials {
                material.transparency = opacity
            }
        }

        for childNode in node.childNodes {
            updateOpacityRecursively(for: childNode, opacity: opacity)
        }
    }

    private func updateDepthRecursively(for node: SCNNode, writesToDepthBuffer: Bool) {
        if let geometry = node.geometry {
            for material in geometry.materials {
                material.writesToDepthBuffer = writesToDepthBuffer
            }
        }

        for childNode in node.childNodes {
            updateDepthRecursively(for: childNode, writesToDepthBuffer: writesToDepthBuffer)
        }
    }
}

private struct ImportedRoomSceneView: UIViewRepresentable {
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

        let panGestureRecognizer = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePanGesture(_:))
        )
        panGestureRecognizer.maximumNumberOfTouches = 1
        scnView.addGestureRecognizer(panGestureRecognizer)

        let rotationGestureRecognizer = UIRotationGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleRotationGesture(_:))
        )
        scnView.addGestureRecognizer(rotationGestureRecognizer)

        context.coordinator.panGestureRecognizer = panGestureRecognizer
        context.coordinator.rotationGestureRecognizer = rotationGestureRecognizer
        context.coordinator.sceneView = scnView
        context.coordinator.interactionMode = interactionMode
        panGestureRecognizer.delegate = context.coordinator
        rotationGestureRecognizer.delegate = context.coordinator

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

        @objc func handlePanGesture(_ gestureRecognizer: UIPanGestureRecognizer) {
            guard interactionMode != .view, let sceneView else {
                cancelDragging()
                return
            }

            let location = gestureRecognizer.location(in: sceneView)

            switch gestureRecognizer.state {
            case .began:
                beginDragging(at: location, in: sceneView)
            case .changed:
                updateDragging(at: location, in: sceneView)
            case .ended, .cancelled, .failed:
                cancelDragging()
            default:
                break
            }
        }

        @objc func handleRotationGesture(_ gestureRecognizer: UIRotationGestureRecognizer) {
            guard interactionMode == .move, let sceneView else {
                cancelDragging()
                return
            }

            let location = gestureRecognizer.location(in: sceneView)

            switch gestureRecognizer.state {
            case .began:
                beginDragging(at: location, in: sceneView)
            case .changed:
                updateRotation(with: gestureRecognizer.rotation)
                gestureRecognizer.rotation = 0
            case .ended, .cancelled, .failed:
                cancelDragging()
            default:
                break
            }
        }

        func cancelDragging() {
            draggedNode = nil
        }

        private func beginDragging(at location: CGPoint, in sceneView: SCNView) {
            let hitResults = sceneView.hitTest(location, options: nil)

            for result in hitResults {
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
                  let intersection = worldPointOnMovementPlane(for: location, in: sceneView, planeY: movementPlaneY) else {
                return
            }

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0
            draggedNode.worldPosition = SCNVector3(intersection.x, movementPlaneY, intersection.z)
            SCNTransaction.commit()
        }

        private func updateRotation(with rotation: CGFloat) {
            guard let draggedNode else {
                return
            }

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0
            draggedNode.eulerAngles.y -= Float(rotation)
            SCNTransaction.commit()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }

        private func overlayAncestor(for node: SCNNode) -> SCNNode? {
            var currentNode: SCNNode? = node

            while let candidate = currentNode {
                if candidate.name?.hasPrefix("external-usdz-overlay") == true {
                    return candidate
                }
                currentNode = candidate.parent
            }

            return nil
        }

        private func worldPointOnMovementPlane(
            for location: CGPoint,
            in sceneView: SCNView,
            planeY: Float
        ) -> SCNVector3? {
            let nearPoint = sceneView.unprojectPoint(SCNVector3(Float(location.x), Float(location.y), 0))
            let farPoint = sceneView.unprojectPoint(SCNVector3(Float(location.x), Float(location.y), 1))
            let direction = farPoint - nearPoint

            guard abs(direction.y) > 0.0001 else {
                return nil
            }

            let distance = (planeY - nearPoint.y) / direction.y
            guard distance.isFinite else {
                return nil
            }

            return nearPoint + (direction * distance)
        }
    }
}

private func +(lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
    SCNVector3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
}

private func -(lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
    SCNVector3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
}

private func *(vector: SCNVector3, scalar: Float) -> SCNVector3 {
    SCNVector3(vector.x * scalar, vector.y * scalar, vector.z * scalar)
}

extension SCNScene: @retroactive Identifiable {
    public var id: ObjectIdentifier {
        ObjectIdentifier(self)
    }
}
