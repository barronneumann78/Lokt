import Foundation

/// Resolves loosely written exercise names (AI drafts, imports, old saved routines)
/// to real library exercises so every exercise mention can open a detail page.
enum ExerciseNameMatcher {
    /// One memoized verdict, tagged with the size of the candidate list it was
    /// computed against. Some callers resolve against a filtered subset of the
    /// library (e.g. the logger's swap sheet excludes exercises already in the
    /// routine). A verdict computed against a subset must never answer for the
    /// full library: that is how fuzzy draft names went "unresolved" app-wide
    /// for the rest of the session, leaving every non-exactly-named exercise
    /// row inert while exactly-named rows kept navigating.
    private struct CachedResolution {
        var listCount: Int
        var resolvedName: String?
    }

    private static var resolutionCache: [String: CachedResolution] = [:]

    /// Drops all memoized resolutions. Call when the exercise library changes
    /// (custom exercises added/edited), since cached "unresolved" or matched
    /// names may no longer be correct against the new list.
    static func invalidateCache() {
        resolutionCache.removeAll()
    }

    static func bestMatch(for name: String, in exercises: [Exercise]) -> Exercise? {
        let cacheKey = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cacheKey.isEmpty else { return nil }

        if let cached = resolutionCache[cacheKey], cached.listCount == exercises.count {
            if let cachedName = cached.resolvedName {
                if let hit = exercises.first(where: { $0.name == cachedName }) {
                    return hit
                }
                // Same size but a different list — recompute below.
            } else {
                return nil
            }
        }

        let match = computeBestMatch(for: name, in: exercises)
        resolutionCache[cacheKey] = CachedResolution(listCount: exercises.count, resolvedName: match?.name)
        return match
    }

    private static func computeBestMatch(for name: String, in exercises: [Exercise]) -> Exercise? {
        let queryTokens = tokens(for: name)
        guard !queryTokens.isEmpty else { return nil }

        var best: (exercise: Exercise, score: Double)?

        for candidate in exercises {
            let candidateTokens = tokens(for: candidate.name)
            guard !candidateTokens.isEmpty else { continue }

            if candidateTokens == queryTokens {
                return candidate
            }

            let overlap = queryTokens.intersection(candidateTokens)
            let candidateIsSubset = overlap == candidateTokens
            let queryIsSubset = overlap == queryTokens
            guard candidateIsSubset || queryIsSubset, overlap.count >= 2 else { continue }

            let unionCount = queryTokens.union(candidateTokens).count
            var score = Double(overlap.count) / Double(unionCount)
            guard score >= 0.6 else { continue }

            // Prefer a candidate fully contained in the query ("Leg Press" for
            // "Leg Press Machine") over one that adds its own extra words
            // ("Calf Press on the Leg Press Machine").
            if candidateIsSubset {
                score += 0.5
            }

            if best == nil || score > best!.score {
                best = (candidate, score)
            }
        }

        return best?.exercise
    }

    private static let abbreviationExpansions: [String: [String]] = [
        "db": ["dumbbell"],
        "dbs": ["dumbbell"],
        "bb": ["barbell"],
        "kb": ["kettlebell"],
        "bw": ["bodyweight"],
        "ohp": ["overhead", "press"],
        "rdl": ["romanian", "deadlift"],
        "sldl": ["stiff", "leg", "deadlift"],
        "alt": ["alternating"]
    ]

    private static let fillerTokens: Set<String> = [
        "the", "a", "an", "with", "using", "w", "for", "of", "and", "or", "to", "on", "exercise"
    ]

    private static func tokens(for name: String) -> Set<String> {
        let lowered = name.lowercased()
        let separators = CharacterSet.alphanumerics.inverted
        let rawTokens = lowered.components(separatedBy: separators).filter { !$0.isEmpty }

        var normalized: Set<String> = []

        for token in rawTokens {
            if let expansion = abbreviationExpansions[token] {
                expansion.forEach { normalized.insert($0) }
                continue
            }

            guard !fillerTokens.contains(token) else { continue }
            normalized.insert(singularized(token))
        }

        return normalized
    }

    private static func singularized(_ token: String) -> String {
        if token.hasSuffix("sses") {
            return String(token.dropLast(2))
        }

        if token.hasSuffix("ss") || token.count <= 2 {
            return token
        }

        if token.hasSuffix("s") {
            return String(token.dropLast())
        }

        return token
    }
}

extension Array where Element == Exercise {
    /// Exact case-insensitive match first, then a conservative fuzzy match.
    /// Returns nil when nothing in the library is a confident match.
    func resolvedExercise(named name: String) -> Exercise? {
        if let exact = exercise(named: name) {
            return exact
        }

        return ExerciseNameMatcher.bestMatch(for: name, in: self)
    }
}
