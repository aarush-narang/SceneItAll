/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
SwiftUI room capture flow backed by RoomCaptureView.
*/

import SwiftUI
import RoomPlan
import UIKit
import Combine
import SceneKit
import ARKit

final class ScanResultHolder {
    static let shared = ScanResultHolder()
    var room: CapturedRoom?
    var frames: [CapturedFrame] = []
    var objectFrames: [String: [CapturedFrame]] = [:]

    func clear() {
        room = nil
        frames = []
        objectFrames = [:]
    }
}

struct RoomCaptureContainerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = RoomCaptureModel()
    @State private var captureViewID = UUID()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                RoomCaptureViewRepresentable(model: model)
                    .id(captureViewID)
                    .ignoresSafeArea()

                if model.isProcessing {
                    ProgressView("Processing scan…")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 32)
                }
            }
            .background(Color.black)
            .navigationTitle(model.isScanning ? "Scan Room" : "Review Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(model.isScanning ? "Cancel" : "Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.isScanning ? "Done" : "Close") {
                        if model.isScanning {
                            model.stopSession()
                        } else {
                            dismiss()
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(model.isScanning)
        .onAppear {
            captureViewID = UUID()
        }
        .onDisappear {
            model.stopSessionIfNeeded()
        }
        .onChange(of: model.isScanComplete) { _, complete in
            if complete { dismiss() }
        }
        .sheet(isPresented: $model.isShowingShareSheet) {
            if let exportURL = model.exportURL {
                ShareSheet(activityItems: [exportURL])
            }
        }
        .alert("Export Failed", isPresented: $model.isShowingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(model.errorMessage)
        }
    }
}

struct RoomCaptureViewRepresentable: UIViewRepresentable {
    @ObservedObject var model: RoomCaptureModel

    func makeCoordinator() -> RoomCaptureCoordinator {
        // Pass frameSampler directly so the coordinator can call it from
        // background RoomCaptureSessionDelegate callbacks without going
        // through the @MainActor-isolated model.
        RoomCaptureCoordinator(model: model, frameSampler: model.frameSampler)
    }

    func makeUIView(context: Context) -> RoomCaptureView {
        let roomCaptureView = RoomCaptureView(frame: .zero)
        roomCaptureView.captureSession.delegate = context.coordinator
        roomCaptureView.delegate = context.coordinator
        model.attach(to: roomCaptureView)
        DispatchQueue.main.async {
            model.startSession()
        }
        return roomCaptureView
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {
        context.coordinator.model = model
    }

    static func dismantleUIView(_ uiView: RoomCaptureView, coordinator: RoomCaptureCoordinator) {
        uiView.captureSession.stop()
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

@MainActor
final class RoomCaptureModel: ObservableObject {
    @Published var isScanning = false
    @Published var isProcessing = false
    @Published var canExport = false
    @Published var isShowingShareSheet = false
    @Published var isShowingError = false
    @Published var errorMessage = ""
    @Published var matchedScene: MatchedScene?
    @Published var isScanComplete = false

    var exportURL: URL?

    let frameSampler = FrameSampler()
    private let uploadClient: ScanUploadClient = {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "FurnitureAPIBaseURL") as? String,
           let url = URL(string: configured) {
            return ScanUploadClient(baseURL: url)
        }
        return ScanUploadClient(baseURL: URL(string: "http://127.0.0.1:8000")!)
    }()

    private weak var roomCaptureView: RoomCaptureView?
    private let roomCaptureSessionConfig = RoomCaptureSession.Configuration()
    private var finalResults: CapturedRoom?

    func attach(to roomCaptureView: RoomCaptureView) {
        self.roomCaptureView = roomCaptureView
    }

    func startSession() {
        guard let roomCaptureView, !isScanning else { return }
        finalResults = nil
        canExport = false
        isProcessing = false
        matchedScene = nil
        isScanComplete = false

        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch cameraStatus {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.beginCapture()
                    } else {
                        self?.errorMessage = "Camera access is required to scan a room. Enable it in Settings > Privacy > Camera."
                        self?.isShowingError = true
                    }
                }
            }
        case .authorized:
            beginCapture()
        default:
            errorMessage = "Camera access is required to scan a room. Enable it in Settings > Privacy > Camera."
            isShowingError = true
        }
    }

    private func beginCapture() {
        guard let roomCaptureView else { return }
        isScanning = true
        roomCaptureView.captureSession.run(configuration: roomCaptureSessionConfig)

        frameSampler.reset()
        if #available(iOS 17.0, *) {
            roomCaptureView.captureSession.arSession.delegate = frameSampler
        }
    }

    func stopSession() {
        guard let roomCaptureView, isScanning else { return }
        isScanning = false
        canExport = false
        isProcessing = true
        roomCaptureView.captureSession.stop()
    }

    func stopSessionIfNeeded() {
        guard isScanning else { return }
        roomCaptureView?.captureSession.stop()
        isScanning = false
        isProcessing = false
    }

    func exportResults() {
        guard let finalResults else { return }

        let destinationFolderURL = FileManager.default.temporaryDirectory.appending(path: "Export")
        let destinationURL = destinationFolderURL.appending(path: "Room.usdz")
        let capturedRoomURL = destinationFolderURL.appending(path: "Room.json")

        do {
            try FileManager.default.createDirectory(at: destinationFolderURL, withIntermediateDirectories: true)
            let jsonData = try JSONEncoder().encode(finalResults)
            try jsonData.write(to: capturedRoomURL)
            try finalResults.export(to: destinationURL, exportOptions: .mesh)
            exportURL = destinationFolderURL
            isShowingShareSheet = true
        } catch {
            errorMessage = error.localizedDescription
            isShowingError = true
        }
    }

    func exportBarebonesUSDZ() {
        guard let finalResults else { return }

        let destinationFolderURL = FileManager.default.temporaryDirectory.appending(path: "BarebonesUSDZExport")
        let usdzURL = destinationFolderURL.appending(path: "RoomShell.usdz")
        let jsonURL = destinationFolderURL.appending(path: "BarebonesRoom.json")

        do {
            try FileManager.default.createDirectory(at: destinationFolderURL, withIntermediateDirectories: true)
            try exportBarebonesJSON(for: finalResults, to: jsonURL)

            let scene = BarebonesRoomSceneBuilder.scene(for: finalResults)
            let didWriteScene = scene.write(to: usdzURL, options: nil, delegate: nil, progressHandler: nil)

            guard didWriteScene else {
                throw BarebonesExportError.usdzExportFailed
            }

            exportURL = destinationFolderURL
            isShowingShareSheet = true
        } catch {
            errorMessage = error.localizedDescription
            isShowingError = true
        }
    }

    private func exportBarebonesJSON(for finalResults: CapturedRoom, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData: Data

        if #available(iOS 17.0, *) {
            let barebonesRoom = BarebonesCapturedRoom(
                identifier: finalResults.identifier,
                story: finalResults.story,
                version: finalResults.version,
                walls: finalResults.walls,
                doors: finalResults.doors,
                windows: finalResults.windows,
                openings: finalResults.openings,
                floors: finalResults.floors,
                sections: finalResults.sections
            )
            jsonData = try encoder.encode(barebonesRoom)
        } else {
            let legacyBarebonesRoom = LegacyBarebonesCapturedRoom(
                identifier: finalResults.identifier,
                walls: finalResults.walls,
                doors: finalResults.doors,
                windows: finalResults.windows,
                openings: finalResults.openings
            )
            jsonData = try encoder.encode(legacyBarebonesRoom)
        }

        try jsonData.write(to: url)
    }

    func uploadAndMatch() async {
        guard let finalResults else { return }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let scene = try await uploadClient.upload(
                room: finalResults,
                frames: frameSampler.snapshot()
            )
            matchedScene = scene
            let matched = scene.objects.filter { $0.isMatched }.count
            let whitebox = scene.objects.filter { !$0.isMatched }.count
            print("matched \(scene.objects.count) objects (\(matched) real, \(whitebox) white-box):")
            for obj in scene.objects {
                let target: String
                if let pid = obj.matchedProductId {
                    target = "\(pid) (\(obj.matchedProductName ?? "?"))"
                } else {
                    target = "WHITE_BOX"
                }
                print("  • \(obj.detectedId) [\(obj.refinedCategory)] → \(target)")
            }
        } catch {
            errorMessage = error.localizedDescription
            isShowingError = true
        }
    }

    func handleProcessedResult(_ processedResult: CapturedRoom) {
        finalResults = processedResult
        canExport = true
        isProcessing = false
        ScanResultHolder.shared.room = processedResult
        ScanResultHolder.shared.frames = frameSampler.snapshot()
        ScanResultHolder.shared.objectFrames = frameSampler.snapshotObjectFrames()
        isScanComplete = true
    }
}

final class RoomCaptureCoordinator: NSObject, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    var model: RoomCaptureModel
    // Held directly (not through the @MainActor model) so background delegate
    // callbacks can call it without an actor hop.
    private let frameSampler: FrameSampler

    init(model: RoomCaptureModel, frameSampler: FrameSampler) {
        self.model = model
        self.frameSampler = frameSampler
    }

    required init?(coder: NSCoder) {
        nil
    }

    func encode(with coder: NSCoder) { }

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        Task { @MainActor in
            if let error {
                model.errorMessage = "Processing error: \(error.localizedDescription)"
                model.isShowingError = true
            }
            model.handleProcessedResult(processedResult)
        }
    }

    /// Fires on a background thread each time RoomPlan updates its room model.
    /// Forward to FrameSampler so it can trigger object-targeted burst capture.
    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        frameSampler.processRoomUpdate(room)
    }

    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: (any Error)?) {
        if let error {
            Task { @MainActor in
                model.errorMessage = "Scan session ended with error: \(error.localizedDescription)"
                model.isShowingError = true
            }
        }
    }
}
