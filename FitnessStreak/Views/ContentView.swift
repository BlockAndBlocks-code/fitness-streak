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
        didSet { rigOverlay?.showRig = showRig }
    }
    
    private let captureSession = AVCaptureSession()
    private let poseDetector = PoseDetector()
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
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }
    
    private func setupRigOverlay() {
        rigOverlay = RigOverlayView(frame: view.bounds)
        rigOverlay.backgroundColor = .black
        rigOverlay.captureSession = captureSession // Передаем сессию для отрисовки видео
        view.addSubview(rigOverlay)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        rigOverlay?.frame = view.bounds
    }
}

class RigOverlayView: UIView {
    var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    var showRig: Bool = false
    var captureSession: AVCaptureSession? {
        didSet { setupPreviewLayer() }
    }
    
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    private let connections: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .rightShoulder),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        (.leftHip, .rightHip),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.neck, .nose)
    ]
    
    private func setupPreviewLayer() {
        guard let session = captureSession else { return }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect
        layer.frame = bounds
        self.layer.addSublayer(layer)
        self.previewLayer = layer
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard showRig, let context = UIGraphicsGetCurrentContext() else { return }
        
        context.setStrokeColor(UIColor.green.cgColor)
        context.setLineWidth(3.0)
        
        for (start, end) in connections {
            drawLine(context: context, from: start, to: end)
        }
        
        context.setFillColor(UIColor.red.cgColor)
        for (_, point) in joints {
            drawDot(context: context, point: point)
        }
    }
    
    // Переводим координаты Vision в координаты UIView
    private func convertPoint(_ visionPoint: CGPoint) -> CGPoint {
        // Если скелет перевернут (голова внизу), замените (1.0 - visionPoint.y) на visionPoint.y
        let x = (1.0 - visionPoint.x) * bounds.width
        let y = (1.0 - visionPoint.y) * bounds.height
        return CGPoint(x: x, y: y)
    }
    
    private func drawLine(context: CGContext, from: VNHumanBodyPoseObservation.JointName, to: VNHumanBodyPoseObservation.JointName) {
        guard let p1 = joints[from], let p2 = joints[to] else { return }
        
        let point1 = convertPoint(p1)
        let point2 = convertPoint(p2)
        
        context.move(to: point1)
        context.addLine(to: point2)
        context.strokePath()
    }
    
    private func drawDot(context: CGContext, point: CGPoint) {
        let p = convertPoint(point)
        context.fillEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
    }
}