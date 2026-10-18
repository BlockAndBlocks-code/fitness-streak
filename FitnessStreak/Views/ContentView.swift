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
                        // Кнопка сброса
                        Button(action: {
                            reps = 0
                            // Если хотите сбрасывать и ударный режим, раскомментируйте строку ниже:
                            // streakManager.resetStreak() 
                        }) {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .padding()
                        
                        Spacer()
                        
                        // Кнопка отладки
                        Button(action: { showRig.toggle() }) {
                            Image(systemName: showRig ? "eye.fill" : "eye.slash.fill")
                                .font(.system(size: 30))
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
                self?.rigOverlay?.updateJoints(joints)
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
        rigOverlay.captureSession = captureSession
        rigOverlay.showRig = self.showRig
        view.addSubview(rigOverlay)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        rigOverlay?.frame = view.bounds
    }
}

class RigOverlayView: UIView {
    var showRig: Bool = false {
        didSet { updateJoints(joints) }
    }
    
    private var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    
    var captureSession: AVCaptureSession? {
        didSet { setupLayers() }
    }
    
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var drawingLayer: CAShapeLayer = CAShapeLayer()
    
    private let connections: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        // Поменяли местами left и right, чтобы соответствовать зеркалу
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.leftShoulder, .rightShoulder)
    ]
    
    private func setupLayers() {
        guard let session = captureSession else { return }
        
        // 1. Слой видео (кладем в самый низ)
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect
        layer.frame = bounds
        self.layer.insertSublayer(layer, at: 0)
        self.previewLayer = layer
        
        // 2. Слой для скелета (кладем поверх видео)
        drawingLayer.frame = bounds
        drawingLayer.strokeColor = UIColor.green.cgColor
        drawingLayer.lineWidth = 3.0
        drawingLayer.fillColor = UIColor.clear.cgColor
        self.layer.addSublayer(drawingLayer)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
        drawingLayer.frame = bounds
    }
    
    func updateJoints(_ newJoints: [VNHumanBodyPoseObservation.JointName: CGPoint]) {
        self.joints = newJoints
        guard showRig else {
            drawingLayer.path = nil
            return
        }
        
        let path = UIBezierPath()
        
        for (start, end) in connections {
            if let p1 = joints[start], let p2 = joints[end] {
                let point1 = convertPoint(p1)
                let point2 = convertPoint(p2)
                path.move(to: point1)
                path.addLine(to: point2)
            }
        }
        
        for (_, point) in joints {
            let p = convertPoint(point)
            path.append(UIBezierPath(ovalIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)))
        }
        
        drawingLayer.path = path.cgPath
    }
    
    private func convertPoint(_ visionPoint: CGPoint) -> CGPoint {
        // Убрали (1.0 - x), так как камера сама по себе зеркалит картинку
        let x = visionPoint.x * bounds.width
        let y = (1.0 - visionPoint.y) * bounds.height
        return CGPoint(x: x, y: y)
    }
}