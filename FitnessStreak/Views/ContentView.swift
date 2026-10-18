import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var streakManager = StreakManager()
    @State private var reps = 0
    @State private var targetReps = 5
    @State private var showRig = false // Кнопка отладки
    
    var body: some View {
        VStack {
            ZStack {
                // Камера
                CameraView(onRepCompleted: {
                    if reps < targetReps {
                        reps += 1
                        if reps == targetReps {
                            streakManager.completeWorkout()
                        }
                    }
                }, showRig: showRig)
                
                // Кнопка включения отладки
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

// Обертка, передающая флаг отладки в контроллер
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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupRigOverlay()
        
        poseDetector.onRepCompleted = { [weak self] in
            DispatchQueue.main.async {
                self?.onRepCompleted?()
            }
        }
        
        // Подписываемся на обновление точек для отрисовки
        poseDetector.$joints
            .receive(on: DispatchQueue.main)
            .sink { [weak self] joints in
                self?.rigOverlay?.joints = joints
                self?.rigOverlay?.setNeedsDisplay()
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    // Импортируем Combine для sink
    import Combine 
    
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
        rigOverlay.isHidden = true // Скрыто по умолчанию
        view.addSubview(rigOverlay)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        rigOverlay?.frame = view.bounds
    }
}

// Слой для отрисовки скелета
class RigOverlayView: UIView {
    var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        context.setStrokeColor(UIColor.green.cgColor)
        context.setLineWidth(3.0)
        
        // Рисуем линии между суставами (Плечо - Локоть - Запястье)
        drawLine(context: context, from: .rightShoulder, to: .rightElbow)
        drawLine(context: context, from: .rightElbow, to: .rightWrist)
        drawLine(context: context, from: .leftShoulder, to: .leftElbow)
        drawLine(context: context, from: .leftElbow, to: .leftWrist)
        
        // Рисуем сами точки
        drawDot(context: context, joint: .rightShoulder)
        drawDot(context: context, joint: .rightElbow)
        drawDot(context: context, joint: .rightWrist)
        drawDot(context: context, joint: .leftShoulder)
        drawDot(context: context, joint: .leftElbow)
        drawDot(context: context, joint: .leftWrist)
    }
    
    private func drawLine(context: CGContext, from: VNHumanBodyPoseObservation.JointName, to: VNHumanBodyPoseObservation.JointName) {
        guard let p1 = joints[from], let p2 = joints[to] else { return }
        
        // Vision возвращает координаты от 0 до 1 (снизу вверх). Переводим их в координаты экрана.
        // Важно: координата Y у UIView идет сверху вниз, поэтому инвертируем.
        let point1 = CGPoint(x: p1.x * bounds.width, y: (1 - p1.y) * bounds.height)
        let point2 = CGPoint(x: p2.x * bounds.width, y: (1 - p2.y) * bounds.height)
        
        context.move(to: point1)
        context.addLine(to: point2)
        context.strokePath()
    }
    
    private func drawDot(context: CGContext, joint: VNHumanBodyPoseObservation.JointName) {
        guard let p = joints[joint] else { return }
        let point = CGPoint(x: p.x * bounds.width, y: (1 - p.y) * bounds.height)
        context.setFillColor(UIColor.red.cgColor)
        context.fillEllipse(in: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
    }
}