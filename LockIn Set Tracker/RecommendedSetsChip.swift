import SwiftUI

/// Small "Rec N" affordance beside a draft's set count: the number the AI
/// actually proposed, offered without being imposed. Drafts open at the app
/// default (3 sets); tapping the chip applies the recommendation. While the
/// shown count already matches, the chip fades out but keeps its footprint,
/// so resolving it never reflows the card — and it comes back if the lifter
/// steps away from the recommendation again. Neutral gray by design.
struct RecommendedSetsChip: View {
    let recommended: Int
    @Binding var count: Int
    var font: Font = .footnote

    private var isApplied: Bool {
        recommended == max(1, count)
    }

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.24)) {
                count = max(1, recommended)
            }
        } label: {
            Text("Rec \(recommended)")
                .font(font.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay {
                    Capsule()
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isApplied ? 0 : 1)
        .disabled(isApplied)
        .accessibilityHidden(isApplied)
        .accessibilityLabel("Coach recommends \(recommended) sets")
        .animation(.easeOut(duration: 0.18), value: isApplied)
    }
}
