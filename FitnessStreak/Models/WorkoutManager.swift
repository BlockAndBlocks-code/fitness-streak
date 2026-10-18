import Foundation

enum ExerciseType: String, Codable {
    case pushups = "Отжимания"
    case squats = "Приседания"
    case plank = "Планка (сек)"
}

struct Exercise: Identifiable, Codable {
    var id = UUID()
    let type: ExerciseType
    var target: Int
}

class WorkoutManager: ObservableObject {
    @Published var exercises: [Exercise] = []
    @Published var isGenerated: Bool = false
    
    private let dateKey = "workoutGenerationDate"
    private let exercisesKey = "currentExercises"
    
    init() {
        loadOrGenerate()
    }
    
    func loadOrGenerate() {
        let defaults = UserDefaults.standard
        let lastDate = defaults.object(forKey: dateKey) as? Date ?? .distantPast
        let calendar = Calendar.current
        
        if !calendar.isDateInToday(lastDate) {
            // Новый день — генерируем новые упражнения
            generateNewWorkout()
            defaults.set(Date(), forKey: dateKey)
        } else {
            // Загружаем старые
            if let data = defaults.data(forKey: exercisesKey),
               let saved = try? JSONDecoder().decode([Exercise].self, from: data) {
                exercises = saved
                isGenerated = true
            } else {
                generateNewWorkout()
            }
        }
    }
    
    func generateNewWorkout() {
        var newExercises: [Exercise] = []
        
        // Выбираем 2 случайных упражнения из 3
        let allTypes: [ExerciseType] = [.pushups, .squats, .plank]
        let selectedTypes = allTypes.shuffled().prefix(2)
        
        for type in selectedTypes {
            switch type {
            case .pushups:
                newExercises.append(Exercise(type: .pushups, target: Int.random(in: 5...15)))
            case .squats:
                newExercises.append(Exercise(type: .squats, target: Int.random(in: 10...25)))
            case .plank:
                newExercises.append(Exercise(type: .plank, target: Int.random(in: 120...300))) // 2-5 минут в секундах
            }
        }
        
        exercises = newExercises
        isGenerated = true
        
        if let data = try? JSONEncoder().encode(newExercises) {
            UserDefaults.standard.set(data, forKey: exercisesKey)
        }
    }
    
    // Метод для принудительного сброса (для кнопки)
    func forceReset() {
        UserDefaults.standard.removeObject(forKey: dateKey)
        generateNewWorkout()
        UserDefaults.standard.set(Date(), forKey: dateKey)
    }
}