import SwiftUI
import UniformTypeIdentifiers

struct ExerciseReorderDropDelegate: DropDelegate {
    let targetExercise: String
    @Binding var exercises: [String]
    @Binding var draggedExercise: String?
    var didReorder: (() -> Void)? = nil

    func dropEntered(info: DropInfo) {
        guard let draggedExercise,
              draggedExercise != targetExercise,
              let fromIndex = exercises.firstIndex(of: draggedExercise),
              let toIndex = exercises.firstIndex(of: targetExercise) else {
            return
        }

        let destination = toIndex > fromIndex ? toIndex + 1 : toIndex
        guard exercises.indices.contains(fromIndex) else { return }

        withAnimation(.snappy) {
            exercises.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: destination)
        }

        didReorder?()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedExercise = nil
        return true
    }
}

struct ExerciseDragHandle: View {
    let exerciseName: String
    @Binding var draggedExercise: String?

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .background(AppTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onDrag {
                draggedExercise = exerciseName
                return NSItemProvider(object: exerciseName as NSString)
            }
    }
}
