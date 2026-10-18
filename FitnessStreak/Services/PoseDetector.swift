import Foundation
import Vision
import AVFoundation

class PoseDetector: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    // Замыкание, которое вызывается при каждом завершенном повторении
    var onRepCompleted: (() -> Void)?
    
    private var isDown = false // Флаг: находится ли человек в нижней точке
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let request = VNDetectHumanBodyPoseRequest { [weak self] request, error in
            guard let results = request.results as? [VNHumanBodyPoseObservation], let result = results.first else { return }
            self?.analyzePose(result)
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([request])
    }
    
    private func analyzePose(_ observation: VNHumanBodyPoseObservation) {
        // Пытаемся получить точки правого или левого плеча и локтя
        guard let rightArm = try? observation.recognizedPoints(.rightArm),
              let leftArm = try? observation.recognizedPoints(.leftArm) else { return }
        
        // Ищем правую руку, если не видно — левую
        let shoulder = rightArm[.rightShoulder]?.location ?? leftArm[.leftShoulder]?.location
        let elbow = rightArm[.rightElbow]?.location ?? leftArm[.leftElbow]?.location
        let wrist = rightArm[.rightWrist]?.location ?? leftArm[.leftWrist]?.location
        
        guard let s = shoulder, let e = elbow, let w = wrist else { return }
        
        let angle = calculateAngle(p1: s, p2: e, p3: w)
        
        // Логика отжимания:
        // Если угол < 100 градусов (рука согнута) - мы "внизу"
        if angle < 100 && !isDown {
            isDown = true
        }
        // Если угол > 150 градусов (рука разогнута) и мы были "внизу" - засчитываем повторение
        else if angle > 150 && isDown {
            isDown = false
            DispatchQueue.main.async { [weak self] in
                self?.onRepCompleted?()
            }
        }
    }
    
    // Функция для расчета угла между тремя точками (плечо, локоть, запястье)
    private func calculateAngle(p1: CGPoint, p2: CGPoint, p3: CGPoint) -> CGFloat {
        let v1 = CGVector(dx: p1.x - p2.x, dy: p1.y - p2.y)
        let v2 = CGVector(dx: p3.x - p2.x, dy: p3.y - p2.y)
        
        let dotProduct = v1.dx * v2.dx + v1.dy * v2.dy
        let magnitude1 = sqrt(v1.dx * v1.dx + v1.dy * v1.dy)
        let magnitude2 = sqrt(v2.dx * v2.dx + v2.dy * v2.dy)
        
        let angleRadians = acos(dotProduct / (magnitude1 * magnitude2))
        return angleRadians * 180 / .pi
    }
}