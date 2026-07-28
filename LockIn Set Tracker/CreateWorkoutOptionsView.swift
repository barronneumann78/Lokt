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
            Text("START HERE")
                .microLabel()

            NavigationLink(destination: CreateRoutineView(onSave: handleChildSave)) {
                optionCard(
                    title: "Create Manually",
                    icon: "square.and.pencil"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var smartToolsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(entryMode == .aiTools ? "ASK LOKT" : "SMART TOOLS")
                .microLabel()

            NavigationLink(destination: AIWorkoutGeneratorView(onSave: handleChildSave)) {
                optionCard(
                    title: "Generate with AI",
                    icon: "sparkles",
                    isHero: true
                )
            }
            .buttonStyle(.plain)

            NavigationLink(destination: SupplementaryWorkoutGeneratorView(onSave: handleChildSave)) {
                optionCard(
                    title: "Add-On Block",
                    icon: "plus.rectangle.on.folder.fill"
                )
            }
            .buttonStyle(.plain)

            NavigationLink(destination: VoiceWorkoutImportView(onSave: handleChildSave)) {
                optionCard(
                    title: "Import by Voice",
                    icon: "waveform.badge.mic"
                )
            }
            .buttonStyle(.plain)

            NavigationLink(destination: WorkoutPhotoImportView(onSave: handleChildSave)) {
                optionCard(
                    title: "Import from Photo",
                    icon: "sparkles.rectangle.stack.fill"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var optionalManualFooter: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BUILD IT YOURSELF")
                .microLabel()

            NavigationLink(destination: CreateRoutineView(onSave: handleChildSave)) {
                optionCard(
                    title: "Create Manually",
                    icon: "square.and.pencil"
                )
            }
            .buttonStyle(.plain)
        }
    }

    // The one hero card carries the volt plate; every other row stays neutral.
    private func optionCard(title: String, icon: String, isHero: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(isHero ? .title2.weight(.bold) : .headline.weight(.semibold))
                .foregroundStyle(isHero ? AppTheme.backgroundTop : AppTheme.textSecondary)
                .padding(isHero ? 14 : 12)
                .background(isHero ? AppTheme.primary : AppTheme.mutedFill)
                .clipShape(RoundedRectangle(cornerRadius: isHero ? 18 : 14, style: .continuous))

            Text(title)
                .font(isHero ? .title3.weight(.bold) : .headline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(isHero ? 18 : 14)
        .surfaceCard(cornerRadius: 20)
    }

    private func handleChildSave() {
        onSave()
        shouldDismissAfterChildSave = true
    }
}
