import Foundation

class StreakManager: ObservableObject {
    @Published var currentStreak: Int = 0
    @Published var lastWorkoutDate: Date? = nil
    
    private let streakKey = "currentStreak"
    private let dateKey = "lastWorkoutDate"
    
    init() {
        currentStreak = UserDefaults.standard.integer(forKey: streakKey)
        lastWorkoutDate = UserDefaults.standard.object(forKey: dateKey) as? Date
    }
    
    func completeWorkout() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        if let lastDate = lastWorkoutDate {
            let last = calendar.startOfDay(for: lastDate)
            let diff = calendar.dateComponents([.day], from: last, to: today).day ?? 0
            
            if diff == 0 {
                // Уже тренировался сегодня
                return
            } else if diff == 1 {
                // Тренировался вчера - увеличиваем streak
                currentStreak += 1
            } else {
                // Пропустил день - сбрасываем
                currentStreak = 1
            }
        } else {
            // Первая тренировка
            currentStreak = 1
        }
        
        lastWorkoutDate = today
        save()
    }
    
    private func save() {
        UserDefaults.standard.set(currentStreak, forKey: streakKey)
        UserDefaults.standard.set(lastWorkoutDate, forKey: dateKey)
    }
}