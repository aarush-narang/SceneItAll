//
//  FrameSampler.swift
//  FurnitureRoomPlacement
//
//  Captures throttled ARKit frames during a RoomPlan scan so the backend
//  matcher has RGB context to embed each detected piece of furniture against.
//
//  Object-targeted burst capture: when RoomPlan detects a new object (or
//  upgrades one to .high confidence), processRoomUpdate(_:) queues a burst
//  so the next N ARFrames are stored under that object's UUID. The backend
//  prefers these targeted frames over the general time-sampled pool.
//

import Foundation
import ARKit
import CoreImage
import RoomPlan
import UIKit

/// One sampled ARKit frame: downscaled JPEG plus the camera pose / intrinsics
/// needed to project a 3D bounding box into pixel space on the backend.
struct CapturedFrame {
    let frameId: String
    let timestamp: TimeInterval
    let jpegData: Data
    let cameraTransform: simd_float4x4   // world-from-camera, ARKit convention
    let cameraIntrinsics: simd_float3x3  // standard pinhole
    let imageWidth: Int
    let imageHeight: Int
}

/// Subscribes to the underlying `ARSession` of a `RoomCaptureSession` and
/// maintains two pools of frames:
///
/// - **General pool**: time-sampled at `targetFPS`, capped at `maxFrames`.
///   Used as a fallback when no object-specific frames exist.
///
/// - **Object burst pool**: keyed by RoomPlan object UUID. Filled when
///   `processRoomUpdate` detects a new object or a confidence upgrade.
///   The backend uses these frames directly, skipping its own frame-scoring
///   loop over the full general pool.
final class FrameSampler: NSObject, ARSessionDelegate {

    // MARK: tunable constants
    private let targetFPS: Double = 1.5
    private let maxFrames: Int = 120
    private let maxImageDimension: CGFloat = 1024
    private let jpegQuality: CGFloat = 0.85

    private let burstCountOnDetect: Int = 5   // frames captured when object first seen
    private let burstCountOnHighConf: Int = 3 // additional frames when confidence → .high

    // MARK: state — all access must be on `queue`
    private let queue = DispatchQueue(label: "frame-sampler.process")
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    // General time-based pool
    private var lastSampleTime: TimeInterval = 0
    private var frames: [CapturedFrame] = []
    private var nextFrameNumber = 0

    // Object-targeted burst pool
    private var activeBursts: [String: Int] = [:]          // objectId → remaining count
    private var objectFrames: [String: [CapturedFrame]] = [:] // objectId → frames
    private var knownObjectIds: Set<String> = []
    private var highConfidenceObjectIds: Set<String> = []

    // MARK: public read

    /// Snapshot of general time-sampled frames. Safe to call from any queue.
    func snapshot() -> [CapturedFrame] {
        queue.sync { frames }
    }

    /// Snapshot of per-object burst frames. Safe to call from any queue.
    func snapshotObjectFrames() -> [String: [CapturedFrame]] {
        queue.sync { objectFrames }
    }

    func reset() {
        queue.sync {
            frames.removeAll()
            objectFrames.removeAll()
            activeBursts.removeAll()
            knownObjectIds.removeAll()
            highConfidenceObjectIds.removeAll()
            lastSampleTime = 0
            nextFrameNumber = 0
        }
    }

    // MARK: RoomPlan integration

    /// Call from `RoomCaptureSessionDelegate.captureSession(_:didUpdate:)` on
    /// every incremental room update. Thread-safe; can be called from any queue.
    func processRoomUpdate(_ room: CapturedRoom) {
        queue.async { [weak self] in
            guard let self else { return }
            for obj in room.objects {
                let id = obj.identifier.uuidString
                if !self.knownObjectIds.contains(id) {
                    self.knownObjectIds.insert(id)
                    self.activeBursts[id] = self.burstCountOnDetect
                } else if obj.confidence == .high, !self.highConfidenceObjectIds.contains(id) {
                    self.highConfidenceObjectIds.insert(id)
                    // Top up only if currently collecting fewer frames than the upgrade burst.
                    self.activeBursts[id] = max(
                        self.activeBursts[id, default: 0],
                        self.burstCountOnHighConf
                    )
                }
            }
        }
    }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let now = frame.timestamp
        let pixelBuffer = frame.capturedImage
        let intrinsics = frame.camera.intrinsics
        let transform = frame.camera.transform

        // All throttle / burst state lives on `queue` — dispatch everything there
        // so we never race on lastSampleTime or activeBursts.
        queue.async { [weak self] in
            guard let self else { return }

            let hasBursts = !self.activeBursts.isEmpty
            let interval = 1.0 / self.targetFPS
            let shouldSampleRegular = now - self.lastSampleTime >= interval

            guard shouldSampleRegular || hasBursts else { return }

            guard let captured = self.makeCapturedFrame(
                pixelBuffer: pixelBuffer,
                cameraTransform: transform,
                cameraIntrinsics: intrinsics,
                timestamp: now
            ) else { return }

            if shouldSampleRegular {
                self.lastSampleTime = now
                self.appendGeneral(captured)
            }

            if hasBursts {
                self.drainBursts(with: captured)
            }
        }
    }

    // MARK: helpers

    private func appendGeneral(_ frame: CapturedFrame) {
        frames.append(frame)
        if frames.count > maxFrames {
            frames.removeFirst(frames.count - maxFrames)
        }
    }

    private func drainBursts(with frame: CapturedFrame) {
        var completed: [String] = []
        for objectId in activeBursts.keys {
            objectFrames[objectId, default: []].append(frame)
            activeBursts[objectId]! -= 1
            if activeBursts[objectId]! <= 0 {
                completed.append(objectId)
            }
        }
        for id in completed {
            activeBursts.removeValue(forKey: id)
        }
    }

    private func makeCapturedFrame(
        pixelBuffer: CVPixelBuffer,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3,
        timestamp: TimeInterval
    ) -> CapturedFrame? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let originalExtent = ciImage.extent
        guard originalExtent.width > 0, originalExtent.height > 0 else { return nil }

        let scale = min(1.0, maxImageDimension / max(originalExtent.width, originalExtent.height))
        let scaled = (scale < 1.0)
            ? ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : ciImage

        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: jpegQuality) else { return nil }

        // Adjust intrinsics for the downscale: principal point and focal length all scale linearly.
        let scaledIntrinsics = scaledIntrinsicsMatrix(cameraIntrinsics, scale: Float(scale))

        let frameNumber = nextFrameNumber
        nextFrameNumber += 1
        let frameId = String(format: "frame_%04d", frameNumber)

        return CapturedFrame(
            frameId: frameId,
            timestamp: timestamp,
            jpegData: jpegData,
            cameraTransform: cameraTransform,
            cameraIntrinsics: scaledIntrinsics,
            imageWidth: cgImage.width,
            imageHeight: cgImage.height
        )
    }

    private func scaledIntrinsicsMatrix(_ k: simd_float3x3, scale: Float) -> simd_float3x3 {
        if scale == 1.0 { return k }
        var scaled = k
        // simd_float3x3 columns: [col0, col1, col2]; element [row, col] = scaled[col][row].
        scaled[0][0] *= scale  // fx
        scaled[1][1] *= scale  // fy
        scaled[2][0] *= scale  // cx
        scaled[2][1] *= scale  // cy
        return scaled
    }
}
