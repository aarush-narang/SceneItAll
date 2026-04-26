import SwiftUI
import SceneKit
import RoomPlan
import UniformTypeIdentifiers
import UIKit

struct DesignsListView: View {
    @StateObject private var viewModel = DesignsListViewModel()

    var body: some View {
        NavigationStack {
            RefreshableScrollView {
                await viewModel.loadDesigns()
            } content: {
                if viewModel.isLoadingDesigns && viewModel.designs.isEmpty {
                    loadingState
                } else if viewModel.designs.isEmpty {
                    emptyState
                } else {
                    designsGrid
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("My Designs")
            .searchable(text: $viewModel.searchText, prompt: "Search designs")
            .task {
                await viewModel.loadDesignsIfNeeded()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.isShowingNewDesignSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.isShowingStyleQuiz = true
                    } label: {
                        Image(systemName: "paintpalette")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $viewModel.isShowingNewDesignSheet) {
                NewDesignSheet(
                    onScan: {
                        viewModel.isShowingNewDesignSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            if RoomCaptureSession.isSupported {
                                viewModel.isShowingScan = true
                            } else {
                                viewModel.isShowingUnsupportedDeviceSheet = true
                            }
                        }
                    },
                    onImportBarebones: {
                        viewModel.isShowingNewDesignSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            viewModel.importMode = .barebones
                            viewModel.isShowingImporter = true
                        }
                    },
                    onImportStripped: {
                        viewModel.isShowingNewDesignSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            viewModel.importMode = .stripFurniture
                            viewModel.isShowingImporter = true
                        }
                    }
                )
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $viewModel.isShowingScan) {
                RoomCaptureContainerView()
            }
            .fullScreenCover(item: $viewModel.importedScene) { scene in
                RoomEditorView(
                    scene: scene,
                    title: viewModel.importedFileName,
                    baseRoomData: viewModel.importedRoomData,
                    initialPlacedObjects: viewModel.importedPlacedObjects
                )
            }
            .sheet(isPresented: $viewModel.isShowingUnsupportedDeviceSheet) {
                NavigationStack {
                    UnsupportedDeviceView()
                        .navigationTitle("Unavailable")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Close") { viewModel.isShowingUnsupportedDeviceSheet = false }
                            }
                        }
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $viewModel.isShowingStyleQuiz) {
                StyleQuizView(
                    initialResult: viewModel.currentStyleQuizResult,
                    showsSkipButton: false
                ) { result in
                    Task { await viewModel.handleStyleQuizCompletion(result) }
                }
            }
            .fileImporter(
                isPresented: $viewModel.isShowingImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                Task { await viewModel.handleImport(result) }
            }
            .alert("Import Failed", isPresented: $viewModel.isShowingImportError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.importErrorMessage)
            }
            .alert("Couldn't Load Designs", isPresented: $viewModel.isShowingDesignsLoadError) {
                Button("Retry") {
                    Task { await viewModel.loadDesigns() }
                }
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.designsLoadErrorMessage)
            }
            .alert("Couldn't Save Preferences", isPresented: $viewModel.isShowingStylePreferencesError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.stylePreferencesErrorMessage)
            }
            .overlay {
                if viewModel.isSavingStylePreferences {
                    ZStack {
                        Color.black.opacity(0.2)
                            .ignoresSafeArea()

                        ProgressView("Saving your preferences...")
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 120)

            ProgressView()
                .controlSize(.large)

            Text("Loading your designs...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 80)

            Image(systemName: "house.lodge")
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundStyle(.tertiary)

            Text("No Designs Yet")
                .font(.title2.weight(.bold))

            Text("Scan a room with LiDAR or import\na design file to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                viewModel.isShowingNewDesignSheet = true
            } label: {
                Label("Create Your First Design", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color.black, in: Capsule())
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Designs Grid

    private var designsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            ForEach(viewModel.filteredDesigns) { design in
                DesignCard(design: design)
            }
        }
        .padding(16)
    }
}

private struct RefreshableScrollView<Content: View>: UIViewRepresentable {
    let onRefresh: @Sendable () async -> Void
    let content: Content

    init(
        onRefresh: @escaping @Sendable () async -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.onRefresh = onRefresh
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onRefresh: onRefresh, rootView: content)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.backgroundColor = UIColor.systemGroupedBackground

        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(context.coordinator, action: #selector(Coordinator.handleRefresh), for: .valueChanged)
        scrollView.refreshControl = refreshControl

        let hostedView = context.coordinator.hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.backgroundColor = UIColor.clear

        scrollView.addSubview(hostedView)

        NSLayoutConstraint.activate([
            hostedView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostedView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostedView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostedView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.hostingController.rootView = content
    }

    final class Coordinator: NSObject {
        let hostingController: UIHostingController<Content>
        private let onRefresh: @Sendable () async -> Void

        init(onRefresh: @escaping @Sendable () async -> Void, rootView: Content) {
            self.onRefresh = onRefresh
            self.hostingController = UIHostingController(rootView: rootView)
        }

        @objc func handleRefresh(_ sender: UIRefreshControl) {
            Task {
                await onRefresh()
                await MainActor.run {
                    sender.endRefreshing()
                }
            }
        }
    }
}

// MARK: - Design Card

private struct DesignCard: View {
    let design: DesignSummary
    @State private var isPressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [design.accentColor.opacity(0.07), design.accentColor.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "cube.transparent")
                    .font(.system(size: 36, weight: .ultraLight))
                    .foregroundStyle(design.accentColor.opacity(0.35))
            }
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(design.name)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)
                    .padding(.leading, 10)

                Text("\(design.roomType.capitalized) \u{00B7} \(design.furnitureCount) items")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10)

                HStack {
                    Text("Created \(design.createdAt, style: .relative) ago")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color(.secondarySystemBackground), in: Circle())
                }
                .padding(.top, 2)
                .padding(.leading, 10)
                .padding(.trailing, 10)
                .padding(.bottom, 4)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)

        }
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
        .scaleEffect(isPressed ? 0.97 : 1)
        .animation(.spring(response: 0.25), value: isPressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { isPressed = $0 }, perform: { })
    }
}

// MARK: - New Design Sheet

private struct NewDesignSheet: View {
    let onScan: () -> Void
    let onImportBarebones: () -> Void
    let onImportStripped: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Design")
                .font(.system(size: 20, weight: .bold))
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)

            VStack(spacing: 10) {
                NewDesignRow(
                    icon: "camera.viewfinder",
                    iconColor: .blue,
                    title: "Scan Room with LiDAR",
                    subtitle: "Use your device camera to capture the room",
                    action: onScan
                )
                NewDesignRow(
                    icon: "square.and.arrow.down",
                    iconColor: .green,
                    title: "Import Room Design",
                    subtitle: "Load a JSON room file with furniture",
                    action: onImportBarebones
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
    }
}

private struct NewDesignRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(iconColor)
                    .frame(width: 44, height: 44)
                    .background(iconColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
