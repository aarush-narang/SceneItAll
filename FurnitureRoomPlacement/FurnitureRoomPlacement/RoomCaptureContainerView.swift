/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
SwiftUI room capture flow backed by RoomCaptureView.
*/

import SwiftUI
import RoomPlan
import UIKit
import Combine
import SceneKit
import ARKit

struct RoomCaptureContainerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = RoomCaptureModel()
    let onScanComplete: (SCNScene, Data, CapturedRoom, [CapturedFrame]) -> Void

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                RoomCaptureViewRepresentable(model: model)
                    .ignoresSafeArea()

                if model.isProcessing {
                    ProgressView("Processing scan")
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
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if model.isScanning {
                        Button("Done") {
                            model.stopSession()
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(model.isScanning)
        .onAppear {
            model.startSession()
        }
        .onDisappear {
            model.stopSessionIfNeeded()
        }
        .alert("Error", isPresented: $model.isShowingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(model.errorMessage)
        }
        .onChange(of: model.scanComplete) { _, complete in
            if complete, let scene = model.barebonesScene, let room = model.finalResults {
                onScanComplete(scene, model.barebonesRoomData ?? Data(), room, model.capturedFrames)
                dismiss()
            }
        }
    }
}

struct RoomCaptureViewRepresentable: UIViewRepresentable {
    @ObservedObject var model: RoomCaptureModel

    func makeCoordinator() -> RoomCaptureCoordinator {
        RoomCaptureCoordinator(model: model)
    }

    func makeUIView(context: Context) -> RoomCaptureView {
        let roomCaptureView = RoomCaptureView(frame: .zero)
        model.attach(to: roomCaptureView)
        roomCaptureView.captureSession.delegate = context.coordinator
        roomCaptureView.delegate = context.coordinator
        return roomCaptureView
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {
        model.attach(to: uiView)
        context.coordinator.model = model
        uiView.captureSession.delegate = context.coordinator
        uiView.delegate = context.coordinator
    }

    static func dismantleUIView(_ uiView: RoomCaptureView, coordinator: RoomCaptureCoordinator) {
        uiView.captureSession.stop()
    }
}

@MainActor
final class RoomCaptureModel: ObservableObject {
    @Published var isScanning = false
    @Published var isProcessing = false
    @Published var isShowingError = false
    @Published var errorMessage = ""
    @Published var scanComplete = false

    let frameSampler = FrameSampler()
    private(set) var finalResults: CapturedRoom?
    private(set) var capturedFrames: [CapturedFrame] = []
    private(set) var barebonesScene: SCNScene?
    private(set) var barebonesRoomData: Data?

    private weak var roomCaptureView: RoomCaptureView?
    private let roomCaptureSessionConfig = RoomCaptureSession.Configuration()

    func attach(to roomCaptureView: RoomCaptureView) {
        self.roomCaptureView = roomCaptureView
    }

    func startSession() {
        guard let roomCaptureView, !isScanning else { return }
        finalResults = nil
        capturedFrames = []
        barebonesScene = nil
        barebonesRoomData = nil
        isProcessing = false
        scanComplete = false
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
        isProcessing = true
        roomCaptureView.captureSession.stop()
    }

    func stopSessionIfNeeded() {
        guard isScanning else { return }
        roomCaptureView?.captureSession.stop()
        isScanning = false
        isProcessing = false
    }

    func handleProcessedResult(_ processedResult: CapturedRoom) {
        finalResults = processedResult
        capturedFrames = frameSampler.snapshot()
        barebonesScene = BarebonesRoomSceneBuilder.scene(for: processedResult)
        barebonesRoomData = generateBarebonesJSON(for: processedResult)
        isProcessing = false
        scanComplete = true
    }

    private func generateBarebonesJSON(for room: CapturedRoom) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            if #available(iOS 17.0, *) {
                let barebonesRoom = BarebonesCapturedRoom(
                    identifier: room.identifier,
                    story: room.story,
                    version: room.version,
                    walls: room.walls,
                    doors: room.doors,
                    windows: room.windows,
                    openings: room.openings,
                    floors: room.floors,
                    sections: room.sections
                )
                return try encoder.encode(barebonesRoom)
            } else {
                let legacyRoom = LegacyBarebonesCapturedRoom(
                    identifier: room.identifier,
                    walls: room.walls,
                    doors: room.doors,
                    windows: room.windows,
                    openings: room.openings
                )
                return try encoder.encode(legacyRoom)
            }
        } catch {
            print("Failed to generate barebones JSON: \(error)")
            return nil
        }
    }
}

final class RoomCaptureCoordinator: NSObject, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    var model: RoomCaptureModel

    init(model: RoomCaptureModel) {
        self.model = model
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
            model.handleProcessedResult(processedResult)
        }
    }
}
