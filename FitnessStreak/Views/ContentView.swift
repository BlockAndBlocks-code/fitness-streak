import SwiftUI

struct ContentView: View {
    @StateObject private var streakManager = StreakManager()
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Ударный режим")
                .font(.largeTitle.bold())
            
            ZStack {
                Circle()
                    .stroke(lineWidth: 20)
                    .opacity(0.1)
                    .foregroundColor(.orange)
                
                Text("\(streakManager.currentStreak)")
                    .font(.system(size: 80, weight: .bold))
                    .foregroundColor(.orange)
            }
            .frame(width: 200, height: 200)
            
            Button("Сделать отжимания (Тест)") {
                streakManager.completeWorkout()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding()
    }
}