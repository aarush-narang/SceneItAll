import SwiftUI
import SceneKit
import UniformTypeIdentifiers

struct RoomEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: RoomEditorViewModel

    init(scene: SCNScene, title: String, baseRoomData: Data, initialPlacedObjects: [PlacedFurnitureObject]) {
        _viewModel = StateObject(wrappedValue: RoomEditorViewModel(
            scene: scene,
            title: title,
            baseRoomData: baseRoomData,
            initialPlacedObjects: initialPlacedObjects
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ImportedRoomSceneView(
                    scene: viewModel.scene,
                    interactionMode: viewModel.furnitureInteractionMode
                )
                .background(Color(white: 0.72))
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    HStack(alignment: .bottom) {
                        ImportedRoomAssistantOverlay(
                            isPresented: $viewModel.isShowingAssistant,
                            draft: $viewModel.assistantDraft,
                            messages: viewModel.assistantMessages,
                            isChatLoading: viewModel.isAssistantLoading,
                            isCleanupLoading: viewModel.isPlacementCleanupLoading,
                            hasPendingPlacementPreview: viewModel.hasPendingPlacementPreview,
                            onSend: viewModel.handleAssistantSend,
                            onPlacementCleanup: viewModel.handlePlacementCleanup,
                            onAcceptPlacementChanges: { viewModel.acceptPlacementCleanupPreview() },
                            onDeclinePlacementChanges: { viewModel.declinePlacementCleanupPreview() }
                        )
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                    editorToolbar
                }
            }
            .navigationTitle(viewModel.resolvedTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundStyle(.blue)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { viewModel.toggleWallDimming() } label: {
                        Image(systemName: viewModel.areWallsDimmed ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showFurnitureCatalog) {
                NavigationStack {
                    FurnitureCatalogListView(
                        showFurnitureCatalog: $viewModel.showFurnitureCatalog,
                        hasOverlayedExternalUSDZ: $viewModel.hasOverlayedExternalUSDZ,
                        scene: viewModel.scene,
                        onFurnitureAdded: viewModel.handleFurnitureAdded
                    )
                }
                .presentationDetents([.fraction(0.92), .large])
                .presentationDragIndicator(.visible)
            }
            .fileExporter(
                isPresented: $viewModel.isShowingSaveExporter,
                document: viewModel.exportDocument,
                contentType: .json,
                defaultFilename: viewModel.defaultExportFileName
            ) { result in
                if case .failure(let error) = result {
                    viewModel.exportErrorMessage = error.localizedDescription
                    viewModel.isShowingExportError = true
                }
            }
            .alert("Unable to Overlay USDZ", isPresented: $viewModel.isShowingOverlayError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("The app could not load the external USDZ asset.")
            }
            .alert("Save Failed", isPresented: $viewModel.isShowingExportError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.exportErrorMessage)
            }
            .alert("Sync Failed", isPresented: $viewModel.isShowingSyncError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.syncErrorMessage)
            }
            .onChange(of: viewModel.hasOverlayedExternalUSDZ) { _, hasOverlay in
                if !hasOverlay { viewModel.furnitureInteractionMode = .view }
            }
            .task {
                await viewModel.restoreSavedFurnitureIfNeeded()
            }
        }
    }

    // MARK: - Bottom Toolbar

    private var editorToolbar: some View {
        HStack(spacing: 8) {
            EditorToolbarButton(icon: "square.grid.2x2", label: "Catalog") {
                viewModel.showFurnitureCatalog = true
            }

            EditorToolbarButton(
                icon: viewModel.furnitureInteractionMode == .move
                    ? "checkmark.circle" : "arrow.up.and.down.and.arrow.left.and.right",
                label: viewModel.furnitureInteractionMode == .move ? "Done" : "Move"
            ) {
                viewModel.toggleMoveMode()
            }
            .opacity(viewModel.hasOverlayedExternalUSDZ ? 1 : 0.4)
            .disabled(!viewModel.hasOverlayedExternalUSDZ)

            EditorToolbarButton(icon: "square.and.arrow.up", label: "Export") {
                viewModel.saveRoomJSON()
            }
            .opacity(viewModel.placedObjects.isEmpty ? 0.4 : 1)
            .disabled(viewModel.placedObjects.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 32)
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.06), radius: 8, y: -2)
        )
    }
}

// MARK: - Toolbar Button

private struct EditorToolbarButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
