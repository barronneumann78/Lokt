import SwiftUI

/// The create-flow hub. Look v2: a 26pt title, micro-label sections, one
/// gradient pill for the AI path (Generate with AI) and every other entry as
/// a hairline option card.
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
                    Text("Create Workout")
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(.bottom, 2)

                    smartToolsSection
                    if entryMode == .allOptions {
                        manualSection
                    } else {
                        optionalManualFooter
                    }
                }
                .padding(.horizontal, AppTheme.screenPadding)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: shouldDismissAfterChildSave) { _, shouldDismiss in
            if shouldDismiss {
                dismiss()
            }
        }
    }

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("START HERE")
                .microLabel(AppTheme.textSecondary)

            NavigationLink(destination: CreateRoutineView(onSave: handleChildSave)) {
                optionCard(
                    title: "Create Manually",
                    icon: "square.and.pencil"
                )
            }
            .buttonStyle(.plain)

            presetPlanRow
        }
    }

    // The preset-plan generator (template-based, no model call) lives here
    // since the Workout tab's CREATE card folded into its header "+" and the
    // pinned GENERATE WORKOUT pill (look v2).
    private var presetPlanRow: some View {
        NavigationLink(destination: PresetWorkoutGeneratorView(onSave: handleChildSave)) {
            optionCard(
                title: "Start with a Preset Plan",
                icon: "list.bullet.rectangle"
            )
        }
        .buttonStyle(.plain)
    }

    private var smartToolsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(entryMode == .aiTools ? "ASK LOKT" : "SMART TOOLS")
                .microLabel(AppTheme.textSecondary)

            // THE gradient pill of the screen: the AI path.
            NavigationLink(destination: AIWorkoutGeneratorView(onSave: handleChildSave)) {
                Text("Generate with AI")
            }
            .buttonStyle(PrimaryButtonStyle(prominence: .ai))
            .padding(.bottom, 4)

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
        VStack(alignment: .leading, spacing: 10) {
            Text("BUILD IT YOURSELF")
                .microLabel(AppTheme.textSecondary)

            NavigationLink(destination: CreateRoutineView(onSave: handleChildSave)) {
                optionCard(
                    title: "Create Manually",
                    icon: "square.and.pencil"
                )
            }
            .buttonStyle(.plain)

            presetPlanRow
        }
    }

    /// Hairline option card: a 40pt hairline glyph circle, 16pt title, quiet
    /// chevron. Neutral — the accent belongs to the gradient pill above.
    private func optionCard(title: String, icon: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 40, height: 40)
                .background(AppTheme.surfaceElevated)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                }

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(AppTheme.rowPadding)
        .contentShape(Rectangle())
        .glassCard(cornerRadius: 18)
    }

    private func handleChildSave() {
        onSave()
        shouldDismissAfterChildSave = true
    }
}
