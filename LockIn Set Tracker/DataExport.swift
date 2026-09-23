import Foundation

/// Builds the "Export My Data" JSON document (Settings → Workout History).
///
/// One self-describing file containing everything the user would lose if the
/// app were deleted: routines, workout sessions, AI preferences, and custom
/// exercises. Payloads are encoded from the REAL model types — never a
/// hand-copied field list that would drift as models grow.
///
/// Deliberately excluded (derived or settings noise, not user data):
/// `exerciseInsightsV1` cache, `userMemoryDigestV1` (pure function of the raw
/// history), discovery-hint counters, accent scheme, and app credentials.
enum DataExport {
    static let schemaName = "lokt-export"
    static let schemaVersion = 1

    /// Top-level export document. Nested model payloads use the same default
    /// Codable encoding as the UserDefaults blobs they were decoded from, so a
    /// future importer reads them back with the plain `JSONDecoder` the app
    /// already uses everywhere.
    struct Document: Codable {
        var schema: String
        var schemaVersion: Int
        var exportDate: String
        var appVersion: String
        var routines: [Routine]
        var workoutSessions: [WorkoutSession]
        var aiUserPreferences: AIUserPreferences
        var customExercises: [Exercise]
    }

    static func buildDocument(
        routines: [Routine],
        sessions: [WorkoutSession],
        preferences: AIUserPreferences,
        customExercises: [Exercise],
        appVersion: String,
        exportedAt: Date
    ) -> Document {
        Document(
            schema: schemaName,
            schemaVersion: schemaVersion,
            exportDate: iso8601.string(from: exportedAt),
            appVersion: appVersion,
            routines: routines,
            workoutSessions: sessions,
            aiUserPreferences: preferences,
            customExercises: customExercises
        )
    }

    /// Deterministic encoding — pretty-printed with sorted keys so two exports
    /// of the same data diff cleanly.
    static func encode(_ document: Document) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    /// `lokt-export-2026-08-30.json`, dated in the user's calendar day.
    static func filename(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return "lokt-export-\(formatter.string(from: date)).json"
    }

    /// Marketing version plus build, e.g. "1.0 (7)". "unknown" outside an app
    /// bundle (e.g. compiled logic checks).
    static var currentAppVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String

        switch (short, build) {
        case let (short?, build?):
            return "\(short) (\(build))"
        case let (short?, nil):
            return short
        case let (nil, build?):
            return "build \(build)"
        default:
            return "unknown"
        }
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
