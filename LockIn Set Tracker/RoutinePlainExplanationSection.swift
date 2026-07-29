import SwiftUI

/// Short 1–2 sentence overview of an AI draft plus an "Explain More, Simply"
/// expansion that fetches a routine-level plain-language explanation from the
/// backend. Used by the AI review screens.
///
/// Explanations are cached per draft version in view state, keyed by draft id.
/// Coach revisions mint a fresh draft UUID, so a revised draft naturally gets a
/// fresh explanation while re-expanding the same version never refetches.
struct RoutinePlainExplanationSection: View {
    let draft: AIGeneratedRoutineDraft

    @State private var explanationsByDraft: [UUID: String] = [:]
    @State private var expandedDraftIDs: Set<UUID> = []
    @State private var loadingDraftID: UUID?
    @State private var errorMessage: String?

    private let explainService = AIRoutineExplainService()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let overview = draft.briefOverview {
                Text(overview)
                    .font(.body)
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isExpanded, let explanation = explanationsByDraft[draft.id] {
                Button {
                    expandedDraftIDs.remove(draft.id)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("IN PLAIN WORDS")
                            .microLabel()

                        Text(explanation)
                            .font(.body)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surfaceCard(cornerRadius: AppTheme.controlCornerRadius)
                }
                .buttonStyle(.plain)
            } else {
                Button(isLoading ? "Explaining..." : "Explain More, Simply") {
                    expand()
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isLoading)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondary)
            }
        }
    }

    private var isExpanded: Bool {
        expandedDraftIDs.contains(draft.id)
    }

    private var isLoading: Bool {
        loadingDraftID == draft.id
    }

    private func expand() {
        errorMessage = nil

        if explanationsByDraft[draft.id] != nil {
            expandedDraftIDs.insert(draft.id)
            return
        }

        guard loadingDraftID != draft.id else { return }
        loadingDraftID = draft.id
        let requestedDraft = draft

        Task { @MainActor in
            do {
                let explanation = try await explainService.plainExplanation(for: requestedDraft)
                explanationsByDraft[requestedDraft.id] = explanation
                expandedDraftIDs.insert(requestedDraft.id)
            } catch {
                if loadingDraftID == requestedDraft.id {
                    errorMessage = error.localizedDescription
                }
            }

            if loadingDraftID == requestedDraft.id {
                loadingDraftID = nil
            }
        }
    }
}
