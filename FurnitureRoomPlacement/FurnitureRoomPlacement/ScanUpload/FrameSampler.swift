//
//  FrameSampler.swift
//  FurnitureRoomPlacement
//
//  Captures throttled ARKit frames during a RoomPlan scan so the backend
//  matcher has RGB context to embed each detected piece of furniture against.
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
/// stashes a downsampled frame at most every `1 / targetFPS` seconds. Caps
/// in-memory frames at `maxFrames` (drops the oldest when exceeded).
final class FrameSampler: NSObject, ARSessionDelegate {

    // MARK: tunable constants
    private let targetFPS: Double = 1.5
    private let maxFrames: Int = 120
    private let maxImageDimension: CGFloat = 1024
    private let jpegQuality: CGFloat = 0.85

    // MARK: state
    private let queue = DispatchQueue(label: "frame-sampler.process")
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private var lastSampleTime: TimeInterval = 0
    private var frames: [CapturedFrame] = []
    private var nextFrameNumber = 0

    /// Snapshot of frames captured so far. Safe to call on the main queue.
    func snapshot() -> [CapturedFrame] {
        queue.sync { frames }
    }

    func reset() {
        queue.sync {
            frames.removeAll()
            lastSampleTime = 0
            nextFrameNumber = 0
        }
    }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let now = frame.timestamp
        let interval = 1.0 / targetFPS
        if now - lastSampleTime < interval { return }
        lastSampleTime = now

        // Hop off ARKit's delegate queue — JPEG encoding can take a few ms.
        let pixelBuffer = frame.capturedImage
        let intrinsics = frame.camera.intrinsics
        let transform = frame.camera.transform

        queue.async { [weak self] in
            guard let self else { return }
            guard let captured = self.makeCapturedFrame(
                pixelBuffer: pixelBuffer,
                cameraTransform: transform,
                cameraIntrinsics: intrinsics,
                timestamp: now
            ) else { return }
            self.append(captured)
        }
    }

    // MARK: helpers

    private func append(_ frame: CapturedFrame) {
        frames.append(frame)
        if frames.count > maxFrames {
            frames.removeFirst(frames.count - maxFrames)
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
