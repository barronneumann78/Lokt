import SwiftUI

/// Collapsed-by-default disclosure for the per-exercise reasoning/tip lines on
/// AI review surfaces. Cards stay clean until the lifter asks for more; the
/// chevron (and, where a card has one, its otherwise-inactive background)
/// toggles the block open. State lives per surface as a `Set<UUID>` of expanded
/// exercise ids, so fresh drafts and revisions (new ids) start collapsed.
enum ExerciseDetailDisclosure {
    /// One snappy spring shared by every review surface so the reveal feels
    /// identical on generator, coach, and import cards.
    static let animation: Animation = .snappy(duration: 0.28)

    static func toggle(_ id: UUID, in expandedIDs: Binding<Set<UUID>>) {
        withAnimation(animation) {
            if expandedIDs.wrappedValue.contains(id) {
                expandedIDs.wrappedValue.remove(id)
            } else {
                expandedIDs.wrappedValue.insert(id)
            }
        }
    }
}

/// Small neutral chevron that opens/closes one exercise's reasoning/tip block.
/// Rendered only when the card actually has something to disclose.
struct ExerciseDetailDisclosureChevron: View {
    let id: UUID
    @Binding var expandedIDs: Set<UUID>
    var font: Font = .subheadline

    private var isExpanded: Bool {
        expandedIDs.contains(id)
    }

    var body: some View {
        Button {
            ExerciseDetailDisclosure.toggle(id, in: $expandedIDs)
        } label: {
            Image(systemName: "chevron.down")
                .font(font.weight(.semibold))
                .foregroundStyle(AppTheme.textTertiary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Hide exercise notes" : "Show exercise notes")
    }
}

extension View {
    /// Lets the otherwise-inactive area of a review card toggle its
    /// reasoning/tip disclosure. Attached as a background so it underlies the
    /// card's real controls — buttons, navigation links, menus, and text
    /// fields sit above it and keep their own hit areas.
    func exerciseDetailDisclosureTapArea(
        id: UUID,
        expandedIDs: Binding<Set<UUID>>,
        enabled: Bool
    ) -> some View {
        background {
            if enabled {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        ExerciseDetailDisclosure.toggle(id, in: expandedIDs)
                    }
            }
        }
    }
}
