import SwiftUI

/// Preset splits. Look v2: 26pt title, the recommended split as a card with
/// a ghost Start, split choices as selection tiles (accent chip fill +
/// accent hairline + gradient check when chosen), template and equipment
/// chips in the chip vocabulary, Create N-Day Split as THE gradient pill,
/// Preview / Save This Day / Adjust Equipment as ghosts, and the day preview
/// as hairline rows. Generation and save paths are untouched.
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
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private static let tileCornerRadius: CGFloat = 18

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
                .padding(.horizontal, AppTheme.screenPadding)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("")
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
            .font(.system(size: 26, weight: .bold))
            .tracking(-0.3)
            .foregroundStyle(AppTheme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 2)
    }

    private func recommendedSection(_ split: WorkoutPresetSplit) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECOMMENDED")
                .microLabel(AppTheme.textSecondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(split.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(split.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Start with \(split.title)") {
                selectedSplitKind = split.kind
                saveSelectedSplit(split)
            }
            .buttonStyle(GhostButtonStyle())
            .disabled(exerciseStore.exercises.isEmpty)
            .opacity(exerciseStore.exercises.isEmpty ? 0.6 : 1)
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private var splitSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CHOOSE ANOTHER SPLIT")
                .microLabel(AppTheme.textSecondary)

            ForEach(WorkoutPresetSplitKind.allCases) { kind in
                if let split = PresetWorkoutLibrary.split(for: kind) {
                    splitTile(split, isSelected: selectedSplitKind == kind) {
                        selectedSplitKind = kind
                    }
                }
            }
        }
    }

    /// Selection tile in the Onboarding vocabulary: 17pt title over the day
    /// count; accent chip fill + accent hairline and a gradient check when
    /// selected, a hairline circle otherwise.
    private func splitTile(_ split: WorkoutPresetSplit, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.tileCornerRadius, style: .continuous)

        return Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(split.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.leading)

                    Text("\(split.templates.count) day\(split.templates.count == 1 ? "" : "s")")
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer(minLength: 12)

                ZStack {
                    if isSelected {
                        Circle()
                            .fill(AppTheme.primaryGradient)

                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(AppTheme.backgroundTop)
                    } else {
                        Circle()
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    }
                }
                .frame(width: 26, height: 26)
            }
            .padding(AppTheme.rowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    shape.fill(AppTheme.accentChipFill)
                }
            }
            .glassCard(cornerRadius: Self.tileCornerRadius)
            .overlay {
                if isSelected {
                    shape.stroke(AppTheme.accentHairline, lineWidth: 1)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "\(split.title), selected" : split.title)
    }

    private func selectedSplitSection(_ split: WorkoutPresetSplit) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SELECTED SPLIT")
                .microLabel(AppTheme.textSecondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(split.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(split.scheduleHint)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("INCLUDED ROUTINES")
                    .microLabel()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(split.templates) { template in
                            Button {
                                selectedTemplateID = template.id
                                preview = nil
                            } label: {
                                TagChip(title: template.routineName, isActive: selectedTemplateID == template.id)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // THE gradient pill of the screen.
            Button("Create \(split.templates.count)-Day Split") {
                saveSelectedSplit(split)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(exerciseStore.exercises.isEmpty)
            .opacity(exerciseStore.exercises.isEmpty ? 0.6 : 1)

            HStack(spacing: 10) {
                Button("Preview Selected Day") {
                    generatePreview()
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(selectedTemplate == nil)
                .opacity(selectedTemplate == nil ? 0.6 : 1)

                Button(showEquipmentOptions ? "Hide Equipment Options" : "Adjust Equipment (Optional)") {
                    showEquipmentOptions.toggle()
                }
                .buttonStyle(GhostButtonStyle())
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("EQUIPMENT")
                .microLabel(AppTheme.textSecondary)

            LazyVGrid(columns: gridColumns, spacing: 10) {
                ForEach(EquipmentType.selectionOptions, id: \.self) { equipment in
                    equipmentTile(equipment, isSelected: selectedEquipment.contains(equipment)) {
                        toggleEquipment(equipment)
                    }
                }
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    /// Multi-select tile in the chip vocabulary (the Settings injury tiles).
    private func equipmentTile(_ equipment: EquipmentType, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous)

        return Button(action: action) {
            HStack(spacing: 8) {
                Text(equipment.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .foregroundStyle(isSelected ? AppTheme.primary : AppTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? AppTheme.accentChipFill : AppTheme.fieldBackground)
            .clipShape(shape)
            .overlay {
                shape.stroke(isSelected ? AppTheme.accentHairline : AppTheme.cardBorder, lineWidth: 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }

    private func previewSection(_ preview: GeneratedPresetWorkout) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DAY PREVIEW")
                        .microLabel(AppTheme.textSecondary)

                    Text(preview.template.routineName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                }

                Spacer()

                TagChip(title: "\(preview.matches.count) exercises")
            }

            VStack(spacing: 0) {
                ForEach(Array(preview.matches.enumerated()), id: \.element.id) { item in
                    if item.offset > 0 {
                        Rectangle()
                            .fill(AppTheme.cardBorder)
                            .frame(height: 1)
                    }

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            ExerciseTextNavigationLink(exerciseName: item.element.exercise.name, exercises: exerciseStore.exercises) {
                                Text(item.element.exercise.name)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .multilineTextAlignment(.leading)
                            }

                            TagChip(title: item.element.role.title)
                        }

                        Spacer(minLength: 8)

                        ExerciseAskButton(
                            context: ExerciseAskContext(name: item.element.exercise.name),
                            askTarget: $askTarget,
                            font: .subheadline,
                            hinted: hints.showAskHint(sessionCount: workoutStore.sessions.count)
                        )
                    }
                    .padding(.vertical, 12)
                }
            }

            if !preview.missingRoles.isEmpty {
                Text("Some optional slots could not be filled with the current equipment settings.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Button("Save This Day as Routine") {
                saveRoutines([preview.asRoutine])
                onSave()
                dismiss()
            }
            .buttonStyle(GhostButtonStyle())
            .disabled(preview.matches.isEmpty)
            .opacity(preview.matches.isEmpty ? 0.6 : 1)
        }
        .padding(AppTheme.cardPadding)
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
