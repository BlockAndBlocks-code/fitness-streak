import Foundation
import Vision
import AVFoundation
import SwiftUI

class PoseDetector: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onRepCompleted: (() -> Void)?
    
    @Published var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    
    private var isDown = false
    private var isStabilized = false
    private var framesCount = 0
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let request = VNDetectHumanBodyPoseRequest { [weak self] request, error in
            guard let results = request.results as? [VNHumanBodyPoseObservation], let result = results.first else { return }
            self?.analyzePose(result)
        }
        
        // ВАЖНО: Фронтальная камера в портрете выдает изображение повернутым.
        // Используем .leftMirrored, чтобы нейросеть видела картинку так же, как и пользователь.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored, options: [:])
        try? handler.perform([request])
    }
    
    private func analyzePose(_ observation: VNHumanBodyPoseObservation) {
        guard let rightArm = try? observation.recognizedPoints(.rightArm),
              let leftArm = try? observation.recognizedPoints(.leftArm) else { return }
        
        let shoulder = rightArm[.rightShoulder]?.location ?? leftArm[.leftShoulder]?.location
        let elbow = rightArm[.rightElbow]?.location ?? leftArm[.leftElbow]?.location
        let wrist = rightArm[.rightWrist]?.location ?? leftArm[.leftWrist]?.location
        
        guard let s = shoulder, let e = elbow, let w = wrist else { return }
        
        let angle = calculateAngle(p1: s, p2: e, p3: w)
        
        if !isStabilized {
            framesCount += 1
            if framesCount > 30 && angle > 140 && angle < 180 {
                isStabilized = true
            }
            return
        }
        
        var newJoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        newJoints[.rightShoulder] = s
        newJoints[.rightElbow] = e
        newJoints[.rightWrist] = w
        if let ls = leftArm[.leftShoulder]?.location, let le = leftArm[.leftElbow]?.location, let lw = leftArm[.leftWrist]?.location {
            newJoints[.leftShoulder] = ls
            newJoints[.leftElbow] = le
            newJoints[.leftWrist] = lw
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.joints = newJoints
        }
        
        if angle < 100 && !isDown {
            isDown = true
        } else if angle > 150 && isDown {
            isDown = false
            DispatchQueue.main.async { [weak self] in
                self?.onRepCompleted?()
            }
        }
    }
    
    private func calculateAngle(p1: CGPoint, p2: CGPoint, p3: CGPoint) -> CGFloat {
        let v1 = CGVector(dx: p1.x - p2.x, dy: p1.y - p2.y)
        let v2 = CGVector(dx: p3.x - p2.x, dy: p3.y - p2.y)
        
        let dotProduct = v1.dx * v2.dx + v1.dy * v2.dy
        let magnitude1 = sqrt(v1.dx * v1.dx + v1.dy * v1.dy)
        let magnitude2 = sqrt(v2.dx * v2.dx + v2.dy * v2.dy)
        
        if magnitude1 == 0 || magnitude2 == 0 { return 0 }
        
        let angleRadians = acos(dotProduct / (magnitude1 * magnitude2))
        return angleRadians * 180 / .pi
    }
}