import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var streakManager = StreakManager()
    @State private var reps = 0
    @State private var targetReps = 5 // Сколько отжиманий нужно сделать за раз
    
    var body: some View {
        VStack {
            // Экран камеры
            CameraView(onRepCompleted: {
                if reps < targetReps {
                    reps += 1
                    // Если достигли цели - засчитываем тренировку!
                    if reps == targetReps {
                        streakManager.completeWorkout()
                    }
                }
            })
            .frame(height: 400)
            .cornerRadius(20)
            .padding()
            
            // HUD с прогрессом
            VStack(spacing: 10) {
                Text("Отжимания: \(reps) / \(targetReps)")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Ударный режим: \(streakManager.currentStreak) 🔥")
                    .font(.title2)
                    .foregroundColor(.orange)
                
                if reps >= targetReps {
                    Text("Тренировка засчитана! Молодец!")
                        .font(.headline)
                        .foregroundColor(.green)
                }
            }
            .padding()
            
            Spacer()
        }
    }
}

// Обертка для камеры, которая связывает AVFoundation с PoseDetector
struct CameraView: UIViewControllerRepresentable {
    let onRepCompleted: () -> Void
    
    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.onRepCompleted = onRepCompleted
        return controller
    }
    
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

class CameraViewController: UIViewController {
    var onRepCompleted: (() -> Void)?
    
    private let captureSession = AVCaptureSession()
    private let poseDetector = PoseDetector()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        
        // Связываем детектор с UI
        poseDetector.onRepCompleted = { [weak self] in
            DispatchQueue.main.async {
                self?.onRepCompleted?()
            }
        }
    }
    
    private func setupCamera() {
        // Запрос камеры (передняя, чтобы видеть себя)
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
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
}