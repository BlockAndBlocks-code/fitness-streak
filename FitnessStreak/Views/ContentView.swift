import SwiftUI
import AVFoundation
import Combine
import Vision

struct ContentView: View {
    @StateObject private var streakManager = StreakManager()
    
    // Состояния игры
    @State private var reps = 0
    @State private var targetReps = 5
    @State private var showRig = false
    @State private var isWorkoutActive = false
    @State private var countdown = 0
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 0) {
            // 1. ВЕРХНЯЯ ЧАСТЬ: Камера
            ZStack {
                CameraView(onRepCompleted: {
                    guard isWorkoutActive else { return }
                    
                    if reps < targetReps {
                        reps += 1
                        if reps == targetReps {
                            streakManager.completeWorkout()
                            isWorkoutActive = false
                        }
                    }
                }, showRig: showRig)
                
                // Таймер обратного отсчета
                if countdown > 0 {
                    Text("\(countdown)")
                        .font(.system(size: 120, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 10)
                }
            }
            .frame(maxHeight: .infinity)
            .background(Color.black)
            
            // 2. НИЖНЯЯ ЧАСТЬ: Кнопки и статистика
            VStack(spacing: 20) {
                HStack {
                    VStack {
                        Text("Ударный режим")
                            .font(.caption).foregroundColor(.gray)
                        Text("\(streakManager.currentStreak) 🔥")
                            .font(.title2).foregroundColor(.orange).bold()
                    }
                    Spacer()
                    VStack {
                        Text("Отжимания")
                            .font(.caption).foregroundColor(.gray)
                        Text("\(reps) / \(targetReps)")
                            .font(.title2).foregroundColor(.white).bold()
                    }
                }
                .padding(.horizontal, 30)
                
                if reps >= targetReps {
                    Text("Тренировка засчитана! Молодец!")
                        .font(.headline).foregroundColor(.green)
                }
                
                HStack(spacing: 20) {
                    // Кнопка сброса
                    Button(action: {
                        reps = 0
                        isWorkoutActive = false
                        countdown = 0
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.title)
                            .padding()
                            .background(Color.gray.opacity(0.3))
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                    
                    // Главная кнопка СТАРТ
                    Button(action: startWorkout) {
                        Text(isWorkoutActive ? "ИДЕТ ТРЕНИРОВКА" : "СТАРТ")
                            .font(.title2.bold())
                            .padding(.horizontal, 40)
                            .padding(.vertical, 15)
                            .background(isWorkoutActive ? Color.gray : Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(30)
                    }
                    .disabled(isWorkoutActive || countdown > 0)
                    
                    // Кнопка отладки
                    Button(action: { showRig.toggle() }) {
                        Image(systemName: showRig ? "eye.fill" : "eye.slash.fill")
                            .font(.title)
                            .padding()
                            .background(Color.gray.opacity(0.3))
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                }
                .padding(.bottom, 30)
            }
            .background(Color(UIColor.systemBackground))
            .onReceive(timer) { _ in
                if countdown > 0 {
                    countdown -= 1
                    if countdown == 0 {
                        isWorkoutActive = true
                    }
                }
            }
        }
        .edgesIgnoringSafeArea(.top)
    }
    
    func startWorkout() {
        reps = 0
        isWorkoutActive = false
        countdown = 3
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
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.leftShoulder, .rightShoulder)
    ]
    
    private func setupLayers() {
        guard let session = captureSession else { return }
        
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect
        layer.frame = bounds
        self.layer.insertSublayer(layer, at: 0)
        self.previewLayer = layer
        
        drawingLayer.frame = bounds
        drawingLayer.strokeColor = UIColor.green.cgColor
        drawingLayer.lineWidth = 4.0
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
            if let p1 = joints[start], let p2 = joints[end],
               isValidPoint(p1), isValidPoint(p2) {
                
                let point1 = convertPoint(p1)
                let point2 = convertPoint(p2)
                path.move(to: point1)
                path.addLine(to: point2)
            }
        }
        
        for (_, point) in joints {
            if isValidPoint(point) {
                let p = convertPoint(point)
                path.append(UIBezierPath(ovalIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)))
            }
        }
        
        drawingLayer.path = path.cgPath
    }
    
    private func isValidPoint(_ point: CGPoint) -> Bool {
        if point.x <= 0.01 || point.x >= 0.99 || point.y <= 0.01 || point.y >= 0.99 {
            return false
        }
        return true
    }
    
    private func convertPoint(_ visionPoint: CGPoint) -> CGPoint {
        let x = visionPoint.x * bounds.width
        let y = (1.0 - visionPoint.y) * bounds.height
        return CGPoint(x: x, y: y)
    }
}