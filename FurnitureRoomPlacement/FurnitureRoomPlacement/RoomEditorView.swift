import SwiftUI
import SceneKit
import UniformTypeIdentifiers

struct RoomEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: RoomEditorViewModel

    init(
        scene: SCNScene,
        title: String,
        baseRoomData: Data,
        initialPlacedObjects: [PlacedFurnitureObject],
        designID: String
    ) {
        _viewModel = StateObject(wrappedValue: RoomEditorViewModel(
            scene: scene,
            title: title,
            baseRoomData: baseRoomData,
            initialPlacedObjects: initialPlacedObjects,
            designID: designID
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ImportedRoomSceneView(
                    scene: viewModel.scene,
                    interactionMode: viewModel.furnitureInteractionMode,
                    onTapObject: { identifier in
                        Task { @MainActor in
                            viewModel.handleObjectTapped(identifier)
                        }
                    }
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
            .sheet(item: $viewModel.selectedObject) { object in
                PlacedObjectDetailSheet(
                    object: object,
                    onDelete: { viewModel.deleteSelectedObject() },
                    onDismiss: { viewModel.selectedObject = nil }
                )
                .presentationDetents([.height(420), .medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.regularMaterial)
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
            .edgesIgnoringSafeArea(.bottom)
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

// MARK: - Placed Object Detail Sheet

private struct PlacedObjectDetailSheet: View {
    let object: PlacedFurnitureObject
    let onDelete: () -> Void
    let onDismiss: () -> Void

    @State private var isConfirmingDelete = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 18)

            if !details.isEmpty {
                detailsCard
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
            }

            Spacer(minLength: 0)

            deleteButton
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground).opacity(0.0))
        .confirmationDialog(
            "Delete \(object.furniture.name) from this room?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) { }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(object.furniture.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary.opacity(0.55))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    // MARK: Details

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(details) { row in
                DetailFactRow(label: row.label, value: row.value)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var details: [PlacedObjectDetailRow] {
        var rows: [PlacedObjectDetailRow] = []

        let category = object.furniture.taxonomyInferred.category
        if !category.isEmpty {
            let leaf = object.furniture.taxonomyIkea.categoryLeaf
            rows.append(.init(label: "Category", value: leaf.isEmpty ? category.capitalized : leaf))
        }

        let material = object.furniture.attributes.materialPrimary
        if !material.isEmpty {
            rows.append(.init(label: "Material", value: material.capitalized))
        }

        let color = object.furniture.attributes.colorPrimary
        if !color.isEmpty {
            rows.append(.init(label: "Color", value: color.capitalized))
        }

        if !dimensionsText.isEmpty {
            rows.append(.init(label: "Size", value: dimensionsText))
        }

        if let rationale = object.rationale, !rationale.isEmpty {
            rows.append(.init(label: "Why It's Here", value: rationale))
        }

        return rows
    }

    // MARK: Delete Button

    private var deleteButton: some View {
        Button { isConfirmingDelete = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                Text("Delete from Room")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.red, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: Helpers

    private var subtitle: String {
        var components: [String] = []
        if object.furniture.price.value > 0 {
            components.append(object.furniture.formattedPrice)
        }
        let inferred = object.furniture.taxonomyInferred.category
        if !inferred.isEmpty {
            components.append(inferred.capitalized)
        }
        return components.joined(separator: " \u{00B7} ")
    }

    private var dimensionsText: String {
        let bbox = object.furniture.dimensionsBbox
        guard bbox.widthM > 0 || bbox.heightM > 0 || bbox.depthM > 0 else { return "" }
        return "\(formatMeters(bbox.widthM)) W \u{00D7} \(formatMeters(bbox.depthM)) D \u{00D7} \(formatMeters(bbox.heightM)) H"
    }

    private func formatMeters(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...2)))) m"
    }
}

private struct PlacedObjectDetailRow: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

private struct DetailFactRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
        }
    }
}
