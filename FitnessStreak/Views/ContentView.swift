import SwiftUI
import AVFoundation
import Combine
import Vision

struct ContentView: View {
    @StateObject private var streakManager = StreakManager()
    @StateObject private var workoutManager = WorkoutManager()
    
    @State private var currentExerciseIndex = 0
    @State private var currentProgress = 0
    @State private var showRig = false
    @State private var isWorkoutActive = false
    @State private var countdown = 0
    @State private var isAllDone = false
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 0) {
            // ВЕРХ: Камера
            ZStack {
                CameraView(
                    currentExercise: workoutManager.exercises.isEmpty ? .pushups : workoutManager.exercises[currentExerciseIndex].type,
                    isActive: isWorkoutActive,
                    onRepCompleted: handleRepCompleted,
                    onPlankTick: handlePlankTick,
                    showRig: showRig
                )
                
                if countdown > 0 {
                    Text("\(countdown)").font(.system(size: 120, weight: .bold)).foregroundColor(.white).shadow(radius: 10)
                }
            }
            .frame(maxHeight: .infinity)
            .background(Color.black)
            
            // НИЗ: Панель управления
            VStack(spacing: 15) {
                // Карточка текущего упражнения
                if !workoutManager.exercises.isEmpty {
                    let ex = workoutManager.exercises[currentExerciseIndex]
                    VStack(spacing: 5) {
                        Text(ex.type.rawValue)
                            .font(.headline).foregroundColor(.gray)
                        
                        if isAllDone {
                            Text("Все выполнено! 🎉").font(.title).bold().foregroundColor(.green)
                        } else {
                            Text("\(currentProgress) / \(ex.target)")
                                .font(.title).bold().foregroundColor(.primary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(15)
                    .padding(.horizontal)
                }
                
                HStack(spacing: 20) {
                    // Сброс
                    Button(action: {
                        currentExerciseIndex = 0
                        currentProgress = 0
                        isWorkoutActive = false
                        isAllDone = false
                        workoutManager.forceReset() // Новые упражнения
                    }) {
                        Image(systemName: "arrow.counterclockwise").font(.title).padding().background(Color.gray.opacity(0.3)).foregroundColor(.white).clipShape(Circle())
                    }
                    
                    // Главная кнопка
                    Button(action: startWorkout) {
                        Text(isAllDone ? "ГОТОВО" : (isWorkoutActive ? "ВЫПОЛНЯЙТЕ" : "СТАРТ"))
                            .font(.title2.bold()).padding(.horizontal, 40).padding(.vertical, 15)
                            .background(isWorkoutActive ? Color.gray : (isAllDone ? Color.gray : Color.green))
                            .foregroundColor(.white).cornerRadius(30)
                    }
                    .disabled(isWorkoutActive || countdown > 0 || isAllDone)
                    
                    // Отладка
                    Button(action: { showRig.toggle() }) {
                        Image(systemName: showRig ? "eye.fill" : "eye.slash.fill").font(.title).padding().background(Color.gray.opacity(0.3)).foregroundColor(.white).clipShape(Circle())
                    }
                }
            }
            .padding(.bottom, 30)
            .background(Color(UIColor.systemBackground))
            .onReceive(timer) { _ in
                if countdown > 0 {
                    countdown -= 1
                    if countdown == 0 { isWorkoutActive = true }
                }
            }
        }
        .edgesIgnoringSafeArea(.top)
    }
    
    func startWorkout() {
        currentProgress = 0
        isWorkoutActive = false
        countdown = 3
    }
    
    func handleRepCompleted() {
        guard isWorkoutActive, !workoutManager.exercises.isEmpty else { return }
        let target = workoutManager.exercises[currentExerciseIndex].target
        
        currentProgress += 1
        if currentProgress >= target {
            finishExercise()
        }
    }
    
    func handlePlankTick() {
        guard isWorkoutActive, !workoutManager.exercises.isEmpty else { return }
        let ex = workoutManager.exercises[currentExerciseIndex]
        guard ex.type == .plank else { return }
        
        currentProgress += 1
        if currentProgress >= ex.target {
            finishExercise()
        }
    }
    
    func finishExercise() {
        isWorkoutActive = false
        
        if currentExerciseIndex + 1 < workoutManager.exercises.count {
            // Переход к следующему упражнению
            currentExerciseIndex += 1
            currentProgress = 0
            countdown = 3 // Новый отсчет 3..2..1
        } else {
            // Все упражнения выполнены!
            isAllDone = true
            streakManager.completeWorkout()
        }
    }
}

struct CameraView: UIViewControllerRepresentable {
    let currentExercise: ExerciseType
    let isActive: Bool
    let onRepCompleted: () -> Void
    let onPlankTick: () -> Void
    let showRig: Bool
    
    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.onRepCompleted = onRepCompleted
        controller.onPlankTick = onPlankTick
        return controller
    }
    
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        uiViewController.showRig = showRig
        uiViewController.currentExercise = currentExercise
        uiViewController.isActive = isActive
    }
}

class CameraViewController: UIViewController {
    var onRepCompleted: (() -> Void)?
    var onPlankTick: (() -> Void)?
    var showRig: Bool = false { didSet { rigOverlay?.showRig = showRig } }
    var currentExercise: ExerciseType = .pushups { didSet { poseDetector.currentExercise = currentExercise } }
    var isActive: Bool = false { didSet { poseDetector.isActive = isActive } }
    
    private let captureSession = AVCaptureSession()
    private let poseDetector = PoseDetector()
    private var rigOverlay: RigOverlayView!
    private var cancellables = Set<AnyCancellable>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupRigOverlay()
        
        poseDetector.onRepCompleted = { [weak self] in DispatchQueue.main.async { self?.onRepCompleted?() } }
        poseDetector.onPlankTick = { [weak self] in DispatchQueue.main.async { self?.onPlankTick?() } }
        
        poseDetector.$joints.receive(on: DispatchQueue.main).sink { [weak self] joints in
            self?.rigOverlay?.updateJoints(joints)
        }.store(in: &cancellables)
    }
    
    private func setupCamera() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        captureSession.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(poseDetector, queue: DispatchQueue(label: "cameraQueue"))
        captureSession.addOutput(output)
        DispatchQueue.global(qos: .userInitiated).async { self.captureSession.startRunning() }
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
    var showRig: Bool = false { didSet { updateJoints(joints) } }
    private var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    var captureSession: AVCaptureSession? { didSet { setupLayers() } }
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var drawingLayer: CAShapeLayer = CAShapeLayer()
    
    private let connections: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.leftShoulder, .rightShoulder),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.leftHip, .rightHip)
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
        guard showRig else { drawingLayer.path = nil; return }
        let path = UIBezierPath()
        for (start, end) in connections {
            if let p1 = joints[start], let p2 = joints[end], isValidPoint(p1), isValidPoint(p2) {
                path.move(to: convertPoint(p1)); path.addLine(to: convertPoint(p2))
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
        return !(point.x <= 0.01 || point.x >= 0.99 || point.y <= 0.01 || point.y >= 0.99)
    }
    
    private func convertPoint(_ visionPoint: CGPoint) -> CGPoint {
        return CGPoint(x: visionPoint.x * bounds.width, y: (1.0 - visionPoint.y) * bounds.height)
    }
}