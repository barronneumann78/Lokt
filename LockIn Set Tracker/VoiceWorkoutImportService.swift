import AVFoundation
import Foundation
import Speech

enum VoiceWorkoutImportError: LocalizedError {
    case microphonePermissionDenied
    case recorderUnavailable
    case recordingNotFound
    case unreadableRecording
    case invalidBackendURL
    case invalidResponse
    case emptyTranscript
    case noExercisesDetected
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is turned off. Allow it in Settings to record a workout request."
        case .recorderUnavailable:
            return "The app could not start recording right now. Try again in a moment."
        case .recordingNotFound:
            return "There was no recording to import."
        case .unreadableRecording:
            return "That voice recording could not be read."
        case .invalidBackendURL:
            return "The AI backend URL is invalid. Update it in Settings before using voice import."
        case .invalidResponse:
            return "The voice import backend responded, but the result could not be understood."
        case .emptyTranscript:
            return "I could not hear enough workout detail in that recording. Try again and speak a little more clearly."
        case .noExercisesDetected:
            return "I transcribed the recording, but I could not build a workout from it yet."
        case .requestFailed(let message):
            return message
        }
    }
}

@MainActor
final class VoiceWorkoutRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var liveTranscript = ""
    @Published private(set) var isLivePreviewAvailable = false

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer = SFSpeechRecognizer()
    private var currentRecordingURL: URL?
    private var audioFile: AVAudioFile?

    func startRecording() async throws {
        let granted = await requestMicrophonePermission()
        guard granted else {
            throw VoiceWorkoutImportError.microphonePermissionDenied
        }

        let speechPermissionStatus = await requestSpeechRecognitionPermission()
        let canShowLivePreview = speechPermissionStatus == .authorized && speechRecognizer != nil

#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
#endif

        let fileURL = Self.makeRecordingURL()
        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let audioFile = try AVAudioFile(forWriting: fileURL, settings: inputFormat.settings)

        let recognitionRequest = canShowLivePreview ? SFSpeechAudioBufferRecognitionRequest() : nil
        recognitionRequest?.shouldReportPartialResults = true
        recognitionRequest?.addsPunctuation = false

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            do {
                try self?.audioFile?.write(from: buffer)
            } catch {
                return
            }

            self?.recognitionRequest?.append(buffer)
        }

        if let recognitionRequest, let speechRecognizer {
            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                Task { @MainActor in
                    if let transcript = result?.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines),
                       !transcript.isEmpty {
                        self?.liveTranscript = transcript
                    }

                    if error != nil || result?.isFinal == true {
                        self?.recognitionTask = nil
                    }
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()

        self.audioEngine = audioEngine
        self.audioFile = audioFile
        self.recognitionRequest = recognitionRequest
        currentRecordingURL = fileURL
        liveTranscript = ""
        isLivePreviewAvailable = canShowLivePreview
        isRecording = true
    }

    func stopRecording() throws -> URL {
        guard let audioEngine, let currentRecordingURL else {
            throw VoiceWorkoutImportError.recordingNotFound
        }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.finish()

        self.audioEngine = nil
        self.audioFile = nil
        self.recognitionRequest = nil
        self.recognitionTask = nil
        self.currentRecordingURL = nil
        isRecording = false

#if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif

        return currentRecordingURL
    }

    func cancelRecording() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        if let currentRecordingURL {
            try? FileManager.default.removeItem(at: currentRecordingURL)
        }

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        audioFile = nil
        currentRecordingURL = nil
        liveTranscript = ""
        isLivePreviewAvailable = false
        isRecording = false

#if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func requestSpeechRecognitionPermission() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private static func makeRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-workout-\(UUID().uuidString)")
            .appendingPathExtension("wav")
    }
}

struct VoiceWorkoutImportPipeline {
    private let transcriber = VoiceWorkoutTranscriptionClient()
    private let matcher = VoiceExerciseMatcher()
    private let classifier = VoiceWorkoutIntentClassifier()
    private let parser = VoiceExercisePhraseParser()
    private let generatorClient = AIWorkoutGeneratorClient()

    func importWorkout(
        from audioFileURL: URL,
        exercises: [Exercise],
        progress: @escaping @MainActor (String) -> Void = { _ in }
    ) async throws -> ImportedWorkoutDraft {
        let parsingResult = try await parseWorkout(
            from: audioFileURL,
            exercises: exercises,
            progress: progress
        )

        return ImportedWorkoutDraft(parsingResult: parsingResult)
    }

    func parseWorkout(
        from audioFileURL: URL,
        exercises: [Exercise],
        progress: @escaping @MainActor (String) -> Void = { _ in }
    ) async throws -> AIWorkoutParsingResult {
        await progress("Uploading your recording...")
        let transcription = try await transcriber.transcribeAudio(at: audioFileURL)
        let transcript = transcription.transcript.nonEmptyOrFallback("")

        guard !transcript.isEmpty else {
            throw VoiceWorkoutImportError.emptyTranscript
        }

        await progress("Understanding your workout request...")
        let intent = classifier.classify(transcript: transcript)

        switch intent {
        case .exerciseList:
            return try buildListParsingResult(from: transcript, exercises: exercises)
        case .workoutRequest:
            await progress("Generating a routine from your transcript...")
            return try await buildGeneratedParsingResult(from: transcript, exercises: exercises)
        }
    }

    private func buildListParsingResult(from transcript: String, exercises: [Exercise]) throws -> AIWorkoutParsingResult {
        let phrases = parser.parsePhrases(from: transcript)
        guard !phrases.isEmpty else {
            throw VoiceWorkoutImportError.noExercisesDetected
        }

        let routineTitle = parser.suggestedTitle(from: transcript)
        let drafts = phrases.map { phrase in
            draftForExerciseName(
                phrase,
                sourceText: phrase,
                dayName: routineTitle,
                setCount: nil,
                repText: nil,
                notes: nil,
                exercises: exercises
            )
        }

        let draft = ImportedWorkoutDraft(
            sourceText: transcript,
            sourceKind: "voice",
            days: [
                ImportedWorkoutDayDraft(
                    name: routineTitle,
                    sourceHeading: transcript,
                    notes: ["Built from a spoken exercise list."],
                    exercises: drafts
                )
            ]
        )

        return draft.parsingResult(routineTitle: routineTitle)
    }

    private func buildGeneratedParsingResult(from transcript: String, exercises: [Exercise]) async throws -> AIWorkoutParsingResult {
        let generatedRoutine = try await generatorClient.generateRoutine(from: transcript)
        let routineNotes = ([generatedRoutine.summary] + generatedRoutine.routineNotes)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let drafts = generatedRoutine.exercises.map { generatedExercise in
            draftForExerciseName(
                generatedExercise.name,
                sourceText: generatedExercise.name,
                dayName: generatedRoutine.title,
                setCount: generatedExercise.sets,
                repText: generatedExercise.reps,
                notes: generatedExercise.notes,
                exercises: exercises
            )
        }

        guard !drafts.isEmpty else {
            throw VoiceWorkoutImportError.noExercisesDetected
        }

        let draft = ImportedWorkoutDraft(
            sourceText: transcript,
            sourceKind: "voice",
            days: [
                ImportedWorkoutDayDraft(
                    name: generatedRoutine.title,
                    sourceHeading: transcript,
                    notes: routineNotes,
                    exercises: drafts
                )
            ]
        )

        return draft.parsingResult(routineTitle: generatedRoutine.title)
    }

    private func draftForExerciseName(
        _ exerciseName: String,
        sourceText: String,
        dayName: String,
        setCount: Int?,
        repText: String?,
        notes: String?,
        exercises: [Exercise]
    ) -> ImportedExerciseDraft {
        let resolution = matcher.resolve(exerciseName: exerciseName, dayName: dayName, exercises: exercises)

        switch resolution {
        case let .matched(exerciseMatch, confidence, candidates):
            return ImportedExerciseDraft(
                sourceText: sourceText,
                exerciseName: exerciseMatch.name,
                matchedExerciseName: exerciseMatch.name,
                matchCandidates: candidates,
                setCount: setCount,
                repText: repText,
                notes: notes ?? "",
                restSeconds: nil,
                intensityNotes: [],
                confidence: confidence,
                isCustomExercise: false,
                customExercise: nil
            )
        case let .custom(candidates):
            return ImportedExerciseDraft(
                sourceText: sourceText,
                exerciseName: exerciseName.titleCasedHeadline(),
                matchedExerciseName: nil,
                matchCandidates: candidates,
                setCount: setCount,
                repText: repText,
                notes: notes ?? "",
                restSeconds: nil,
                intensityNotes: [],
                confidence: .low,
                isCustomExercise: true,
                customExercise: nil
            )
        }
    }
}

private struct VoiceWorkoutTranscriptionClient {
    func transcribeAudio(at fileURL: URL) async throws -> VoiceWorkoutTranscriptionResult {
        guard !AIBackendConfiguration.candidateBaseURLs.isEmpty else {
            throw VoiceWorkoutImportError.invalidBackendURL
        }

        let baseURL = try await verifyBackendReachability()

        let audioData: Data

        do {
            audioData = try Data(contentsOf: fileURL)
        } catch {
            throw VoiceWorkoutImportError.unreadableRecording
        }

        let (data, response): (Data, URLResponse)

        do {
            let result = try await sendAIBackendRequest(
                path: "api/ai/voice-to-workout/transcribe",
                timeout: 180,
                body: try JSONEncoder().encode(
                    VoiceWorkoutTranscriptionRequest(
                        audioBase64: audioData.base64EncodedString(),
                        fileName: fileURL.lastPathComponent,
                        mimeType: mimeType(for: fileURL)
                    )
                )
            )
            (data, response) = (result.data, result.response)
        } catch {
            throw VoiceWorkoutImportError.requestFailed(
                detailedBackendErrorMessage(for: error, endpoint: baseURL.appending(path: "api/ai/voice-to-workout/transcribe"))
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VoiceWorkoutImportError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let decodedError = try? JSONDecoder().decode(VoiceWorkoutTranscriptionErrorEnvelope.self, from: data) {
                throw VoiceWorkoutImportError.requestFailed(decodedError.error)
            }

            throw VoiceWorkoutImportError.requestFailed(
                "The voice import backend returned an error (\(httpResponse.statusCode))."
            )
        }

        guard let decoded = try? JSONDecoder().decode(VoiceWorkoutTranscriptionResponseEnvelope.self, from: data) else {
            throw VoiceWorkoutImportError.invalidResponse
        }

        let transcript = decoded.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            throw VoiceWorkoutImportError.emptyTranscript
        }

        return VoiceWorkoutTranscriptionResult(
            transcript: transcript,
            model: decoded.model,
            durationSeconds: decoded.durationSeconds
        )
    }

    private func verifyBackendReachability() async throws -> URL {
        var lastError: Error = VoiceWorkoutImportError.requestFailed("The voice import backend is not responding correctly.")

        for baseURL in AIBackendConfiguration.candidateBaseURLs {
            let healthURL = baseURL.appending(path: "health")
            var request = URLRequest(url: healthURL)
            request.httpMethod = "GET"
            request.timeoutInterval = 8

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    lastError = VoiceWorkoutImportError.requestFailed(
                        "The voice import backend is not responding correctly. Check that your backend URL in Settings matches the running server."
                    )
                    continue
                }

                AIBackendConfiguration.persistWorkingBaseURL(baseURL)
                return baseURL
            } catch {
                lastError = error

                if AIBackendConfiguration.isLocalTestingURL(baseURL),
                   isRetryableAIBackendConnectionError(error) {
                    continue
                }

                throw VoiceWorkoutImportError.requestFailed(
                    detailedBackendErrorMessage(for: error, endpoint: healthURL)
                )
            }
        }

        let fallbackEndpoint = AIBackendConfiguration.candidateBaseURLs.first?.appending(path: "health")
            ?? URL(string: AIBackendConfiguration.defaultBaseURLString)?.appending(path: "health")
            ?? URL(fileURLWithPath: "/health")

        throw VoiceWorkoutImportError.requestFailed(
            detailedBackendErrorMessage(for: lastError, endpoint: fallbackEndpoint)
        )
    }

    private func detailedBackendErrorMessage(for error: Error, endpoint: URL) -> String {
        let host = endpoint.host(percentEncoded: false) ?? AIBackendConfiguration.currentBaseURLString

        if case let VoiceWorkoutImportError.requestFailed(message) = error {
            return message
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "The voice import backend took too long to respond. Make sure it is still running and try a shorter recording."
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
                return "I could not reach the voice import backend at \(host). Make sure your local backend is running and the backend URL in Settings is correct. \(AIBackendConfiguration.localTestingHint)"
            default:
                break
            }
        }

        return "I could not reach the voice import backend. Make sure your server is running and the backend URL in Settings is correct. \(AIBackendConfiguration.localTestingHint)"
    }

    private func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "wav":
            return "audio/wav"
        case "m4a":
            return "audio/m4a"
        default:
            return "application/octet-stream"
        }
    }
}

private enum VoiceWorkoutIntent {
    case exerciseList
    case workoutRequest
}

private struct VoiceWorkoutIntentClassifier {
    private let requestSignals = [
        "make me", "build me", "create", "design", "give me",
        "i want", "i need", "can you", "put together"
    ]

    private let programmingSignals = [
        "minute", "minutes", "only", "dumbbell", "barbell", "home gym",
        "beginner", "advanced", "intermediate", "push day", "pull day",
        "leg day", "upper", "lower", "full body"
    ]

    private let workoutRequestSignals = [
        "workout", "routine", "session", "program",
        "smith machine", "cable", "cables",
        "uses only", "using only", "with only"
    ]

    private let parser = VoiceExercisePhraseParser()

    func classify(transcript: String) -> VoiceWorkoutIntent {
        let normalized = transcript.matchNormalized()
        let parsedPhrases = parser.parsePhrases(from: transcript)

        if normalized.contains(anyOf: requestSignals) {
            return .workoutRequest
        }

        if normalized.contains(anyOf: workoutRequestSignals), normalized.wordCount >= 4 {
            return .workoutRequest
        }

        if parsedPhrases.count >= 3 {
            return .exerciseList
        }

        if normalized.contains(anyOf: programmingSignals), parsedPhrases.count <= 2 {
            return .workoutRequest
        }

        if normalized.contains(" day"), normalized.wordCount >= 4, parsedPhrases.count <= 2 {
            return .workoutRequest
        }

        return parsedPhrases.count >= 2 ? .exerciseList : .workoutRequest
    }
}

private struct VoiceExercisePhraseParser {
    func parsePhrases(from transcript: String) -> [String] {
        let normalized = transcript
            .replacingOccurrences(of: "\n", with: ", ")
            .replacingOccurrences(of: #"\bthen\b|\bnext\b|\bafter that\b|\bplus\b"#, with: ",", options: .regularExpression)
            .replacingOccurrences(of: #"\s+and\s+"#, with: ", ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        return normalized
            .components(separatedBy: CharacterSet(charactersIn: ",;|"))
            .map(cleanPhrase)
            .filter { !$0.isEmpty && $0.containsLetters }
            .uniquePreservingOrder()
    }

    func suggestedTitle(from transcript: String) -> String {
        let normalized = transcript.matchNormalized()

        if normalized.contains("push") { return "Voice Push Day" }
        if normalized.contains("pull") { return "Voice Pull Day" }
        if normalized.contains(anyOf: ["legs", "leg day", "lower"]) { return "Voice Leg Day" }
        if normalized.contains("upper") { return "Voice Upper Day" }
        if normalized.contains(anyOf: ["full body", "fullbody"]) { return "Voice Full Body" }

        return "Voice Workout"
    }

    private func cleanPhrase(_ phrase: String) -> String {
        phrase
            .replacingOccurrences(of: #"^(please|okay|ok|hey|um|uh)\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^(i want|i need|give me|make me|build me)\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r-–—:."))
            .titleCasedHeadline()
    }
}

private enum VoiceExerciseMatchResolution {
    case matched(Exercise, ImportedExerciseConfidence, [ImportedExerciseMatchCandidate])
    case custom([ImportedExerciseMatchCandidate])
}

private struct VoiceExerciseMatcher {
    func resolve(exerciseName: String, dayName: String, exercises: [Exercise]) -> VoiceExerciseMatchResolution {
        let normalizedQuery = normalize(exerciseName)
        let queryTokens = Set(normalizedQuery.split(separator: " ").map(String.init))
        let dayTokens = Set(normalize(dayName).split(separator: " ").map(String.init))

        let candidates = exercises.map { exercise -> ImportedExerciseMatchCandidate in
            let normalizedExerciseName = normalize(exercise.name)
            let exerciseTokens = Set(normalizedExerciseName.split(separator: " ").map(String.init))

            let tokenScore = jaccardScore(lhs: queryTokens, rhs: exerciseTokens)
            let editScore = normalizedSimilarity(lhs: normalizedQuery, rhs: normalizedExerciseName)
            let containmentBonus = normalizedExerciseName.contains(normalizedQuery) || normalizedQuery.contains(normalizedExerciseName) ? 0.12 : 0
            let leadingTokenBonus = leadingTokenScore(lhs: normalizedQuery, rhs: normalizedExerciseName)
            let dayContextBonus = dayContextScore(dayTokens: dayTokens, exercise: exercise)
            let exactBonus = normalizedQuery == normalizedExerciseName ? 0.24 : 0

            let score = min(1.0, 0.42 * tokenScore + 0.38 * editScore + containmentBonus + leadingTokenBonus + dayContextBonus + exactBonus)
            return ImportedExerciseMatchCandidate(name: exercise.name, score: score)
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

            return lhs.score > rhs.score
        }

        guard let best = candidates.first,
              let matchedExercise = exercises.first(where: { $0.name == best.name }) else {
            return .custom([])
        }

        let runnerUpScore = candidates.dropFirst().first?.score ?? 0
        let confidenceGap = best.score - runnerUpScore
        let topCandidates = Array(candidates.prefix(5))

        if best.score >= 0.86 && confidenceGap >= 0.07 {
            return .matched(matchedExercise, .high, topCandidates)
        }

        if best.score >= 0.74 {
            return .matched(matchedExercise, .medium, topCandidates)
        }

        return .custom(topCandidates)
    }

    private func normalize(_ value: String) -> String {
        var output = value.lowercased()
        let replacements: [(String, String)] = [
            (#"(?<![a-z])db(?![a-z])"#, "dumbbell"),
            (#"(?<![a-z])bb(?![a-z])"#, "barbell"),
            (#"(?<![a-z])ohp(?![a-z])"#, "overhead press"),
            (#"(?<![a-z])rdl(?![a-z])"#, "romanian deadlift"),
            (#"(?<![a-z])sldl(?![a-z])"#, "stiff leg deadlift"),
            (#"\blat\s+raise(s)?\b"#, "lateral raise"),
            (#"\bflys\b|\bflies\b|\bflyes\b"#, "fly"),
            (#"\bpressdowns?\b"#, "pushdown"),
            (#"\btri[ -]?cep\b"#, "triceps"),
            (#"\btri\b"#, "triceps"),
            (#"\bbi\b"#, "biceps"),
            (#"\bsmith\s+incline\s+press\b"#, "smith machine incline bench press"),
            (#"\bdb\s+bench\b"#, "dumbbell bench press"),
            (#"\bbb\s+bench\b"#, "barbell bench press"),
            (#"\bcable\s+flys?\b"#, "cable fly"),
            (#"\bpullup\b"#, "pull up"),
            (#"\bchinup\b"#, "chin up")
        ]

        for (pattern, replacement) in replacements {
            output = output.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }

        output = output
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return output
    }

    private func jaccardScore(lhs: Set<String>, rhs: Set<String>) -> Double {
        guard !lhs.isEmpty || !rhs.isEmpty else { return 0 }
        let intersection = lhs.intersection(rhs).count
        let union = lhs.union(rhs).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    private func normalizedSimilarity(lhs: String, rhs: String) -> Double {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)

        guard !lhsChars.isEmpty || !rhsChars.isEmpty else { return 1 }
        guard !lhsChars.isEmpty, !rhsChars.isEmpty else { return 0 }

        var distances = Array(0...rhsChars.count)

        for (leftIndex, leftChar) in lhsChars.enumerated() {
            var previous = distances[0]
            distances[0] = leftIndex + 1

            for (rightIndex, rightChar) in rhsChars.enumerated() {
                let old = distances[rightIndex + 1]
                if leftChar == rightChar {
                    distances[rightIndex + 1] = previous
                } else {
                    distances[rightIndex + 1] = min(previous, distances[rightIndex], old) + 1
                }
                previous = old
            }
        }

        let maxLength = max(lhsChars.count, rhsChars.count)
        return 1 - Double(distances[rhsChars.count]) / Double(maxLength)
    }

    private func leadingTokenScore(lhs: String, rhs: String) -> Double {
        let lhsTokens = lhs.split(separator: " ")
        let rhsTokens = rhs.split(separator: " ")
        let count = min(lhsTokens.count, rhsTokens.count)
        guard count > 0 else { return 0 }

        var matches = 0
        for index in 0..<count where lhsTokens[index] == rhsTokens[index] {
            matches += 1
        }

        return matches > 0 ? min(0.16, Double(matches) * 0.05) : 0
    }

    private func dayContextScore(dayTokens: Set<String>, exercise: Exercise) -> Double {
        guard !dayTokens.isEmpty else { return 0 }

        let muscleTokens = Set((exercise.metadata.primaryMuscles + exercise.metadata.secondaryMuscles + [exercise.muscleGroup.rawValue])
            .flatMap { normalize($0).split(separator: " ").map(String.init) })

        let overlap = dayTokens.intersection(muscleTokens).count
        if overlap > 0 {
            return min(0.08, Double(overlap) * 0.03)
        }

        if dayTokens.contains("push"), [.chest, .shoulders, .arms].contains(exercise.muscleGroup) {
            return 0.04
        }

        if dayTokens.contains("pull"), [.back, .arms].contains(exercise.muscleGroup) {
            return 0.04
        }

        if dayTokens.contains("legs") || dayTokens.contains("lower"), exercise.muscleGroup == .legs {
            return 0.04
        }

        if dayTokens.contains("upper"), [.chest, .back, .shoulders, .arms].contains(exercise.muscleGroup) {
            return 0.03
        }

        return 0
    }
}

private struct VoiceWorkoutTranscriptionRequest: Codable {
    var audioBase64: String
    var fileName: String
    var mimeType: String
}

private struct VoiceWorkoutTranscriptionResponseEnvelope: Codable {
    var transcript: String
    var model: String?
    var durationSeconds: Double?
}

private struct VoiceWorkoutTranscriptionErrorEnvelope: Codable {
    var error: String
}

private extension String {
    var wordCount: Int {
        split(separator: " ").count
    }

    var containsLetters: Bool {
        rangeOfCharacter(from: .letters) != nil
    }

    func matchNormalized() -> String {
        lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9/\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func titleCasedHeadline() -> String {
        matchNormalized()
            .split(separator: " ")
            .map { token -> String in
                if token.count <= 3, token.allSatisfy({ $0.isNumber || $0 == "/" }) {
                    return String(token)
                }

                return token.prefix(1).uppercased() + token.dropFirst()
            }
            .joined(separator: " ")
            .replacingOccurrences(of: " Db ", with: " DB ")
            .replacingOccurrences(of: " Bb ", with: " BB ")
    }

    func nonEmptyOrFallback(_ fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    func contains(anyOf values: [String]) -> Bool {
        values.contains(where: contains)
    }
}

private extension Array where Element == String {
    func uniquePreservingOrder() -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for value in self {
            let key = value.lowercased()
            if seen.insert(key).inserted {
                result.append(value)
            }
        }

        return result
    }
}
