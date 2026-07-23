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
                VStack(alignment: .leading, spacing: 24) {
                    smartToolsSection
                    if entryMode == .allOptions {
                        manualSection
                    } else {
                        optionalManualFooter
                    }
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

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Start Here")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            NavigationLink(destination: CreateRoutineView(onSave: handleChildSave)) {
                optionCard(
                    title: "Create Manually",
                    icon: "square.and.pencil",
                    accent: AppTheme.primary,
                    isPrimary: true
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var smartToolsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(entryMode == .aiTools ? "Ask Lokt" : "Smart Tools")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            NavigationLink(destination: AIWorkoutGeneratorView(onSave: handleChildSave)) {
                optionCard(
                    title: "Generate with AI",
                    icon: "sparkles",
                    accent: AppTheme.accent
                )
            }
            .buttonStyle(.plain)

            NavigationLink(destination: SupplementaryWorkoutGeneratorView(onSave: handleChildSave)) {
                optionCard(
                    title: "Add-On Block",
                    icon: "plus.rectangle.on.folder.fill",
                    accent: AppTheme.primary
                )
            }
            .buttonStyle(.plain)

            NavigationLink(destination: VoiceWorkoutImportView(onSave: handleChildSave)) {
                optionCard(
                    title: "Import by Voice",
                    icon: "waveform.badge.mic",
                    accent: AppTheme.success
                )
            }
            .buttonStyle(.plain)

            NavigationLink(destination: WorkoutPhotoImportView(onSave: handleChildSave)) {
                optionCard(
                    title: "Import from Photo",
                    icon: "sparkles.rectangle.stack.fill",
                    accent: AppTheme.secondary
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var optionalManualFooter: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Prefer to build it yourself?")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            NavigationLink(destination: CreateRoutineView(onSave: handleChildSave)) {
                optionCard(
                    title: "Create Manually",
                    icon: "square.and.pencil",
                    accent: AppTheme.primary,
                    isPrimary: true
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func optionCard(title: String, icon: String, accent: Color, isPrimary: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.title2.weight(.bold))
                .foregroundStyle(isPrimary ? AppTheme.textPrimary : accent)
                .padding(14)
                .background(isPrimary ? AppTheme.surfaceElevated : AppTheme.mutedFill)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(16)
        .surfaceCard(cornerRadius: 20, border: isPrimary ? AppTheme.primary.opacity(0.45) : AppTheme.cardBorder)
    }

    private func handleChildSave() {
        onSave()
        shouldDismissAfterChildSave = true
    }
}
