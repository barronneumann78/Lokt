import SwiftUI

struct PresetWorkoutGeneratorView: View {
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @EnvironmentObject private var workoutStore: WorkoutStore
    @ObservedObject private var hints = DiscoveryHints.shared
    @State private var selectedSplitKind: WorkoutPresetSplitKind = .fullBodyBeginner
    @State private var selectedTemplateID: String?
    @State private var preview: GeneratedPresetWorkout?
    @State private var selectedEquipment: Set<EquipmentType> = Set(EquipmentType.selectionOptions)
    @State private var showEquipmentOptions = false
    @State private var askTarget: ExerciseAskContext?

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var recommendedSplitKind: WorkoutPresetSplitKind {
        .fullBodyBeginner
    }

    private var recommendedSplit: WorkoutPresetSplit? {
        PresetWorkoutLibrary.split(for: recommendedSplitKind)
    }

    private var selectedSplit: WorkoutPresetSplit? {
        PresetWorkoutLibrary.split(for: selectedSplitKind)
    }

    private var selectedTemplate: WorkoutPresetTemplate? {
        selectedSplit?.templates.first(where: { $0.id == selectedTemplateID }) ?? selectedSplit?.templates.first
    }

    private var equipmentProfile: EquipmentAccessProfile {
        EquipmentAccessProfile(availableEquipment: selectedEquipment)
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection

                    if let recommendedSplit {
                        recommendedSection(recommendedSplit)
                    }

                    splitSection

                    if let selectedSplit {
                        selectedSplitSection(selectedSplit)
                    }

                    if showEquipmentOptions {
                        equipmentSection
                    }

                    if let preview {
                        previewSection(preview)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("Preset Splits")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: configureInitialSelection)
        .onChange(of: selectedSplitKind) { _, _ in
            selectedTemplateID = selectedSplit?.templates.first?.id
            preview = nil
        }
        .sheet(item: $askTarget) { context in
            ExerciseAskCoachSheet(context: context)
        }
    }

    private var headerSection: some View {
        Text("Start with a split and keep it easy.")
            .font(.system(size: 30, weight: .bold))
            .tracking(-0.5)
            .foregroundStyle(AppTheme.textPrimary)
    }

    private func recommendedSection(_ split: WorkoutPresetSplit) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("RECOMMENDED")
                .microLabel()

            Text(split.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            Text(split.subtitle)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

            Button("Start with \(split.title)") {
                selectedSplitKind = split.kind
                saveSelectedSplit(split)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(exerciseStore.exercises.isEmpty)
            .opacity(exerciseStore.exercises.isEmpty ? 0.6 : 1)
        }
        .padding(20)
        .glassCard()
    }

    private var splitSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CHOOSE ANOTHER SPLIT")
                .microLabel()

            ForEach(WorkoutPresetSplitKind.allCases) { kind in
                if let split = PresetWorkoutLibrary.split(for: kind) {
                    Button {
                        selectedSplitKind = kind
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(split.title)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(AppTheme.textPrimary)

                                Text("\(split.templates.count) day\(split.templates.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(AppTheme.textSecondary)
                            }

                            Spacer()

                            Image(systemName: selectedSplitKind == kind ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selectedSplitKind == kind ? AppTheme.textPrimary : AppTheme.textTertiary)
                        }
                        .padding(16)
                        .background(selectedSplitKind == kind ? AppTheme.surfaceElevated : AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(selectedSplitKind == kind ? AppTheme.textTertiary : AppTheme.cardBorder, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .glassCard()
    }

    private func selectedSplitSection(_ split: WorkoutPresetSplit) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SELECTED SPLIT")
                .microLabel()

            Text(split.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            Text(split.scheduleHint)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

            Text("INCLUDED ROUTINES")
                .microLabel()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(split.templates) { template in
                        Button {
                            selectedTemplateID = template.id
                            preview = nil
                        } label: {
                            Text(template.routineName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(selectedTemplateID == template.id ? AppTheme.backgroundTop : AppTheme.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedTemplateID == template.id ? AppTheme.textPrimary : AppTheme.mutedFill)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button(showEquipmentOptions ? "Hide Equipment Options" : "Adjust Equipment (Optional)") {
                showEquipmentOptions.toggle()
            }
            .buttonStyle(SecondaryButtonStyle())

            Button("Create \(split.templates.count)-Day Split") {
                saveSelectedSplit(split)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(exerciseStore.exercises.isEmpty)
            .opacity(exerciseStore.exercises.isEmpty ? 0.6 : 1)

            Button("Preview Selected Day") {
                generatePreview()
            }
            .buttonStyle(PrimaryButtonStyle(fill: AppTheme.surfaceElevated))
            .disabled(selectedTemplate == nil)
            .opacity(selectedTemplate == nil ? 0.6 : 1)
        }
        .padding(20)
        .glassCard()
    }

    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("EQUIPMENT")
                .microLabel()

            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(EquipmentType.selectionOptions, id: \.self) { equipment in
                    Button {
                        toggleEquipment(equipment)
                    } label: {
                        Text(equipment.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedEquipment.contains(equipment) ? AppTheme.backgroundTop : AppTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(selectedEquipment.contains(equipment) ? AppTheme.textPrimary : AppTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(AppTheme.cardBorder, lineWidth: selectedEquipment.contains(equipment) ? 0 : 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .glassCard()
    }

    private func previewSection(_ preview: GeneratedPresetWorkout) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DAY PREVIEW")
                        .microLabel()

                    Text(preview.template.routineName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                }

                Spacer()

                Text("\(preview.matches.count) exercises")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppTheme.mutedFill)
                    .clipShape(Capsule())
            }

            ForEach(preview.matches) { match in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        ExerciseTextNavigationLink(exerciseName: match.exercise.name, exercises: exerciseStore.exercises) {
                            Text(match.exercise.name)
                                .font(.headline)
                                .foregroundStyle(AppTheme.textPrimary)
                        }

                        Spacer(minLength: 8)

                        ExerciseAskButton(
                            context: ExerciseAskContext(name: match.exercise.name),
                            askTarget: $askTarget,
                            font: .subheadline,
                            hinted: hints.showAskHint(sessionCount: workoutStore.sessions.count)
                        )
                    }

                    Text(match.role.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(14)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if !preview.missingRoles.isEmpty {
                Text("Some optional slots could not be filled with the current equipment settings.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Button("Save This Day as Routine") {
                saveRoutines([preview.asRoutine])
                onSave()
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(preview.matches.isEmpty)
            .opacity(preview.matches.isEmpty ? 0.6 : 1)
        }
        .padding(20)
        .glassCard()
    }

    private func configureInitialSelection() {
        if selectedTemplateID == nil {
            selectedTemplateID = selectedSplit?.templates.first?.id
        }
    }

    private func generatePreview() {
        guard let selectedTemplate else { return }

        preview = PresetWorkoutGenerator.generate(
            template: selectedTemplate,
            from: exerciseStore.exercises,
            equipmentProfile: equipmentProfile
        )
    }

    private func saveSelectedSplit(_ split: WorkoutPresetSplit) {
        let routines = split.templates
            .map {
                PresetWorkoutGenerator.generate(
                    template: $0,
                    from: exerciseStore.exercises,
                    equipmentProfile: equipmentProfile
                )
            }
            .filter { !$0.matches.isEmpty }
            .map(\.asRoutine)

        guard !routines.isEmpty else { return }

        saveRoutines(routines)
        onSave()
        dismiss()
    }

    private func toggleEquipment(_ equipment: EquipmentType) {
        if selectedEquipment.contains(equipment) {
            if selectedEquipment.count > 1 {
                selectedEquipment.remove(equipment)
            }
        } else {
            selectedEquipment.insert(equipment)
        }

        preview = nil
    }

    private func saveRoutines(_ routinesToAdd: [Routine]) {
        for routine in routinesToAdd {
            workoutStore.addRoutine(routine)
        }
    }
}

private extension EquipmentType {
    static var selectionOptions: [EquipmentType] {
        allCases.filter { $0 != .other }
    }
}
