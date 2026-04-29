import SwiftUI

struct CreateWorkoutOptionsView: View {
    enum EntryMode {
        case allOptions
        case aiTools
    }

    var entryMode: EntryMode = .allOptions
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var shouldDismissAfterChildSave = false

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    headerSection
                    smartToolsSection
                    if entryMode == .allOptions {
                        manualSection
                    } else {
                        optionalManualFooter
                    }
                    trustSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("Create Workout")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: shouldDismissAfterChildSave) { _, shouldDismiss in
            if shouldDismiss {
                dismiss()
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(entryMode == .aiTools ? "Choose how Lokt should help." : "Choose how you want to start.")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            Text(entryMode == .aiTools ? "Pick the AI flow that fits how you want to ask." : "Manual first, smart tools when you want a shortcut.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(20)
        .glassCard()
    }

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Start Here")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            NavigationLink(destination: CreateRoutineView(onSave: handleChildSave)) {
                optionCard(
                    title: "Create Manually",
                    subtitle: "Pick exercises and build the routine yourself.",
                    icon: "square.and.pencil",
                    accent: AppTheme.primary,
                    isPrimary: true
                )
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .glassCard()
    }

    private var smartToolsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(entryMode == .aiTools ? "Ask Lokt" : "Smart Tools")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            NavigationLink(destination: AIWorkoutGeneratorView(onSave: handleChildSave)) {
                optionCard(
                    title: "Generate with AI",
                    subtitle: "Describe the workout and review the draft.",
                    icon: "sparkles",
                    accent: AppTheme.accent
                )
            }
            .buttonStyle(.plain)

            NavigationLink(destination: SupplementaryWorkoutGeneratorView(onSave: handleChildSave)) {
                optionCard(
                    title: "Add-On Block",
                    subtitle: "Build a finisher, warm-up, or recovery block.",
                    icon: "plus.rectangle.on.folder.fill",
                    accent: AppTheme.primary
                )
            }
            .buttonStyle(.plain)

            NavigationLink(destination: VoiceWorkoutImportView(onSave: handleChildSave)) {
                optionCard(
                    title: "Import by Voice",
                    subtitle: "Speak the workout and confirm the matches.",
                    icon: "waveform.badge.mic",
                    accent: AppTheme.success
                )
            }
            .buttonStyle(.plain)

            NavigationLink(destination: WorkoutPhotoImportView(onSave: handleChildSave)) {
                optionCard(
                    title: "Import from Photo",
                    subtitle: "Pull a plan from a screenshot or photo.",
                    icon: "sparkles.rectangle.stack.fill",
                    accent: AppTheme.secondary
                )
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .glassCard()
    }

    private var optionalManualFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prefer to build it yourself?")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            NavigationLink(destination: CreateRoutineView(onSave: handleChildSave)) {
                optionCard(
                    title: "Create Manually",
                    subtitle: "Pick exercises and build the routine yourself.",
                    icon: "square.and.pencil",
                    accent: AppTheme.primary,
                    isPrimary: true
                )
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .glassCard()
    }

    private var trustSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review before save")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Text("AI, voice, and photo tools all stop at a review screen before anything gets saved.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(20)
        .glassCard()
    }

    private func optionCard(title: String, subtitle: String, icon: String, accent: Color, isPrimary: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2.weight(.bold))
                .foregroundStyle(isPrimary ? AppTheme.textPrimary : accent)
                .padding(14)
                .background(isPrimary ? AppTheme.surfaceElevated : AppTheme.mutedFill)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.top, 4)
        }
        .padding(18)
        .surfaceCard(cornerRadius: 20, border: isPrimary ? AppTheme.primary.opacity(0.45) : AppTheme.cardBorder)
    }

    private func handleChildSave() {
        onSave()
        shouldDismissAfterChildSave = true
    }
}
