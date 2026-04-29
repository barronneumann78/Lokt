import Foundation

enum ExerciseMediaCatalog {
    private static let gifByExerciseName: [String: String] = [
        "Dumbbell front raise": "3eGE2JC.gif",
        "Kettlebell Pistol Squat": "5bpPTHv.gif",
        "Cable Seated Crunch": "8xUv4J7.gif",
        "Smith Machine Incline Bench Press": "5v7KYld.gif",
        "Smith machine leg press": "7zdxRTl.gif",
        "Seated cable biceps curl": "8oYqOt9.gif",
        "Standing barbell calf raise": "8ozhUIZ.gif",
    ]

    static func imageName(for exerciseName: String) -> String? {
        gifByExerciseName[exerciseName]
    }

    static func gifURL(for imageName: String) -> URL? {
        guard imageName.lowercased().hasSuffix(".gif") else { return nil }
        return Bundle.main.url(forResource: imageName, withExtension: nil, subdirectory: "ExerciseGIFs")
            ?? Bundle.main.url(forResource: imageName, withExtension: nil)
    }
}
