import Foundation
import Vision
import AVFoundation
import SwiftUI
import Combine

class PoseDetector: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onRepCompleted: (() -> Void)?
    var onPlankTick: (() -> Void)?
    
    @Published var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    
    var currentExercise: ExerciseType = .pushups
    var isActive: Bool = false
    
    private var isDown = false
    private var isStabilized = false
    private var framesCount = 0
    private var lastPlankTime = Date()
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let request = VNDetectHumanBodyPoseRequest { [weak self] request, error in
            guard let results = request.results as? [VNHumanBodyPoseObservation], let result = results.first else { return }
            self?.analyzePose(result)
        }
        
        // ИСПРАВЛЕНИЕ: Ориентация .right для поворота кадра
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        try? handler.perform([request])
    }
    
    private func analyzePose(_ observation: VNHumanBodyPoseObservation) {
        guard let allPoints = try? observation.recognizedPoints(.all) else { return }
        
        var newJoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        for (key, point) in allPoints { newJoints[key] = point.location }
        DispatchQueue.main.async { [weak self] in self?.joints = newJoints }
        
        guard isActive else { return }
        
        switch currentExercise {
        case .pushups:
            checkPushups(allPoints)
        case .squats:
            checkSquats(allPoints)
        case .plank:
            checkPlank(allPoints)
        }
    }
    
    private func checkPushups(_ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) {
        let shoulder = points[.rightShoulder]?.location ?? points[.leftShoulder]?.location
        let elbow = points[.rightElbow]?.location ?? points[.leftElbow]?.location
        let wrist = points[.rightWrist]?.location ?? points[.leftWrist]?.location
        
        guard let s = shoulder, let e = elbow, let w = wrist else { return }
        let angle = calculateAngle(p1: s, p2: e, p3: w)
        
        if !isStabilized {
            framesCount += 1
            if framesCount > 30 && angle > 140 { isStabilized = true }
            return
        }
        
        if angle < 100 && !isDown { isDown = true }
        else if angle > 150 && isDown {
            isDown = false
            triggerRep()
        }
    }
    
    private func checkSquats(_ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) {
        let hip = points[.rightHip]?.location ?? points[.leftHip]?.location
        let knee = points[.rightKnee]?.location ?? points[.leftKnee]?.location
        let ankle = points[.rightAnkle]?.location ?? points[.leftAnkle]?.location
        
        guard let h = hip, let k = knee, let a = ankle else { return }
        let angle = calculateAngle(p1: h, p2: k, p3: a)
        
        if !isStabilized {
            framesCount += 1
            if framesCount > 30 && angle > 150 { isStabilized = true }
            return
        }
        
        if angle < 110 && !isDown { isDown = true }
        else if angle > 160 && isDown {
            isDown = false
            triggerRep()
        }
    }
    
    private func checkPlank(_ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) {
        guard let s = points[.rightShoulder]?.location ?? points[.leftShoulder]?.location,
              let h = points[.rightHip]?.location ?? points[.leftHip]?.location else { return }
        
        if abs(s.y - h.y) > 0.2 { return }
        
        let now = Date()
        if now.timeIntervalSince(lastPlankTime) >= 1.0 {
            lastPlankTime = now
            DispatchQueue.main.async { [weak self] in self?.onPlankTick?() }
        }
    }
    
    private func triggerRep() {
        DispatchQueue.main.async { [weak self] in self?.onRepCompleted?() }
    }
    
    private func calculateAngle(p1: CGPoint, p2: CGPoint, p3: CGPoint) -> CGFloat {
        let v1 = CGVector(dx: p1.x - p2.x, dy: p1.y - p2.y)
        let v2 = CGVector(dx: p3.x - p2.x, dy: p3.y - p2.y)
        let dot = v1.dx * v2.dx + v1.dy * v2.dy
        let mag1 = sqrt(v1.dx * v1.dx + v1.dy * v1.dy)
        let mag2 = sqrt(v2.dx * v2.dx + v2.dy * v2.dy)
        if mag1 == 0 || mag2 == 0 { return 0 }
        return acos(dot / (mag1 * mag2)) * 180 / .pi
    }
}