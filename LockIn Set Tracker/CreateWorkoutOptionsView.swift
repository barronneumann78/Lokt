import SwiftUI

/// The create-flow hub. Look v2: a 26pt title, micro-label sections, three
/// equal gradient-marked AI tiles (describe / voice / photo) and every other
/// entry as a hairline option card.
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

    /// Three equal AI entry tiles — text, voice and photo are the same kind of
    /// action, so none of them gets to be "the" AI button. Add-On Block appends
    /// to an existing routine and stays a row beneath.
    private var smartToolsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(entryMode == .aiTools ? "ASK LOKT" : "SMART TOOLS")
                .microLabel(AppTheme.textSecondary)

            HStack(spacing: 10) {
                NavigationLink(destination: AIWorkoutGeneratorView(onSave: handleChildSave)) {
                    aiTile(title: "Describe", icon: "text.bubble.fill")
                }
                .buttonStyle(.plain)

                NavigationLink(destination: VoiceWorkoutImportView(onSave: handleChildSave)) {
                    aiTile(title: "Voice", icon: "waveform")
                }
                .buttonStyle(.plain)

                NavigationLink(destination: WorkoutPhotoImportView(onSave: handleChildSave)) {
                    aiTile(title: "Photo", icon: "camera.fill")
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 4)

            NavigationLink(destination: SupplementaryWorkoutGeneratorView(onSave: handleChildSave)) {
                optionCard(
                    title: "Add-On Block",
                    icon: "plus.rectangle.on.folder.fill"
                )
            }
            .buttonStyle(.plain)
        }
    }

    /// Equal-weight AI tile: a 44pt gradient glyph circle over a 15pt title.
    /// The gradient marks "this talks to Lokt"; all three share it equally.
    private func aiTile(title: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.backgroundTop)
                .frame(width: 44, height: 44)
                .background(AppTheme.primaryGradient)
                .clipShape(Circle())
                .primaryGlow()

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .contentShape(Rectangle())
        .glassCard(cornerRadius: 18)
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
    /// chevron. Neutral — the gradient belongs to the AI tiles above.
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
