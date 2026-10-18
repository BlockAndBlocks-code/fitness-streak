import SwiftUI
import AVFoundation
import Combine
import Vision

struct ContentView: View {
    @StateObject private var streakManager = StreakManager()
    @State private var reps = 0
    @State private var targetReps = 5
    @State private var showRig = false
    
    var body: some View {
        VStack {
            ZStack {
                CameraView(onRepCompleted: {
                    if reps < targetReps {
                        reps += 1
                        if reps == targetReps {
                            streakManager.completeWorkout()
                        }
                    }
                }, showRig: showRig)
                
                VStack {
                    HStack {
                        Spacer()
                        Button(action: { showRig.toggle() }) {
                            Image(systemName: showRig ? "eye.fill" : "eye.slash.fill")
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .padding()
                    }
                    Spacer()
                }
            }
            .frame(height: 400)
            .cornerRadius(20)
            .padding()
            
            VStack(spacing: 10) {
                Text("Отжимания: \(reps) / \(targetReps)")
                    .font(.title).fontWeight(.bold)
                
                Text("Ударный режим: \(streakManager.currentStreak) 🔥")
                    .font(.title2).foregroundColor(.orange)
                
                if reps >= targetReps {
                    Text("Тренировка засчитана! Молодец!")
                        .font(.headline).foregroundColor(.green)
                }
            }
            .padding()
            
            Spacer()
        }
    }
}

struct CameraView: UIViewControllerRepresentable {
    let onRepCompleted: () -> Void
    let showRig: Bool
    
    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.onRepCompleted = onRepCompleted
        return controller
    }
    
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        uiViewController.showRig = showRig
    }
}

class CameraViewController: UIViewController {
    var onRepCompleted: (() -> Void)?
    var showRig: Bool = false {
        didSet { rigOverlay?.isHidden = !showRig }
    }
    
    private let captureSession = AVCaptureSession()
    private let poseDetector = PoseDetector()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var rigOverlay: RigOverlayView!
    private var cancellables = Set<AnyCancellable>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupRigOverlay()
        
        poseDetector.onRepCompleted = { [weak self] in
            DispatchQueue.main.async {
                self?.onRepCompleted?()
            }
        }
        
        poseDetector.$joints
            .receive(on: DispatchQueue.main)
            .sink { [weak self] joints in
                self?.rigOverlay?.joints = joints
                self?.rigOverlay?.setNeedsDisplay()
            }
            .store(in: &cancellables)
    }
    
    private func setupCamera() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        
        captureSession.addInput(input)
        
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(poseDetector, queue: DispatchQueue(label: "cameraQueue"))
        captureSession.addOutput(output)
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }
    
    private func setupRigOverlay() {
        rigOverlay = RigOverlayView(frame: view.bounds)
        rigOverlay.backgroundColor = .clear
        rigOverlay.isHidden = true
        rigOverlay.previewLayer = previewLayer
        view.addSubview(rigOverlay)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        rigOverlay?.frame = view.bounds
    }
}

class RigOverlayView: UIView {
    var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    weak var previewLayer: AVCaptureVideoPreviewLayer?
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext(), let preview = previewLayer else { return }
        
        context.setStrokeColor(UIColor.green.cgColor)
        context.setLineWidth(4.0)
        context.setLineCap(.round)
        
        drawLine(context: context, from: .rightShoulder, to: .rightElbow, preview: preview)
        drawLine(context: context, from: .rightElbow, to: .rightWrist, preview: preview)
        drawLine(context: context, from: .leftShoulder, to: .leftElbow, preview: preview)
        drawLine(context: context, from: .leftElbow, to: .leftWrist, preview: preview)
        
        context.setFillColor(UIColor.red.cgColor)
        drawDot(context: context, joint: .rightShoulder, preview: preview)
        drawDot(context: context, joint: .rightElbow, preview: preview)
        drawDot(context: context, joint: .rightWrist, preview: preview)
        drawDot(context: context, joint: .leftShoulder, preview: preview)
        drawDot(context: context, joint: .leftElbow, preview: preview)
        drawDot(context: context, joint: .leftWrist, preview: preview)
    }
    
    // Исправленный метод: layerPointConverted(fromCaptureDevicePoint:)
    private func convertPoint(_ visionPoint: CGPoint, preview: AVCaptureVideoPreviewLayer) -> CGPoint {
        let layerPoint = preview.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: visionPoint.x, y: 1.0 - visionPoint.y))
        return layerPoint
    }
    
    private func drawLine(context: CGContext, from: VNHumanBodyPoseObservation.JointName, to: VNHumanBodyPoseObservation.JointName, preview: AVCaptureVideoPreviewLayer) {
        guard let p1 = joints[from], let p2 = joints[to] else { return }
        
        let point1 = convertPoint(p1, preview: preview)
        let point2 = convertPoint(p2, preview: preview)
        
        context.move(to: point1)
        context.addLine(to: point2)
        context.strokePath()
    }
    
    private func drawDot(context: CGContext, joint: VNHumanBodyPoseObservation.JointName, preview: AVCaptureVideoPreviewLayer) {
        guard let p = joints[joint] else { return }
        let point = convertPoint(p, preview: preview)
        context.fillEllipse(in: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
    }
}