import AppKit
import InputMethodKit
import JevIMECore
import os

/// Raw keys stay available until a word is decided, including keys typed during inference.
@MainActor
final class CompositionSession {
    /// How the committed text for a word was chosen.
    enum SelectionSource {
        case automaticOrMemory
        case inlinePreview
        case languageShortcut
        case correction
    }

    private struct Word {
        let id = UUID()
        var raw: String
        var separator: String
    }

    private struct Conversion {
        var id = UUID()
        let raw: String
        let selected: String
        var separator: String
        let before: String
        var range: NSRange
        var languageAlternative: String? = nil
        var source: SelectionSource = .automaticOrMemory
        var text: String { selected + separator }
    }

    private struct Feedback {
        let conversionID: UUID
        let raw: String
        let before: String
        let rejected: String
        let separator: String
        let range: NSRange
        let expectedText: String
        let source: SelectionSource
    }

    private let client: any IMKTextInput
    private let shortcuts: ShortcutSettings
    private let corrections: CorrectionStore
    private let localClient: LocalDecisionClient?
    private let previewDefaults: UserDefaults
    private let hostBundleID: String?
    private let onPreviewStart: (() -> Void)?
    private let onPreview: ((String?) -> Void)?
    private let onError: (String) -> Void
    private let logger = Logger(subsystem: "com.yeop.inputmethod.JevType", category: "Composition")
    private let diagnosticLogger = Logger(subsystem: "com.yeop.inputmethod.JevType", category: "CommandDiagnostics")
    let diagnosticID = UUID().uuidString
    private var words: [Word] = []
    private var raw = ""
    private var context = ""
    private var contextSelection: NSRange?
    private var task: Task<Void, Never>?
    private var generation = 0
    private var active = true
    private var lastCommit: Conversion?
    private var feedback: Feedback?

    init(client: any IMKTextInput, shortcuts: ShortcutSettings? = nil, corrections: CorrectionStore? = nil,
         localClient: LocalDecisionClient? = nil, previewDefaults: UserDefaults = .standard,
         hostBundleID: String? = nil,
         onPreviewStart: (() -> Void)? = nil,
         onPreview: ((String?) -> Void)? = nil,
         onError: @escaping (String) -> Void) {
        self.client = client
        self.shortcuts = shortcuts ?? .shared
        self.corrections = corrections ?? CorrectionStore.shared
        self.localClient = localClient
        self.previewDefaults = previewDefaults
        self.hostBundleID = hostBundleID
        self.onPreviewStart = onPreviewStart
        self.onPreview = onPreview
        self.onError = onError
        logDiagnostic("session_created")
    }

    func handle(_ event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .control]).isEmpty == false {
            commitHangul()
            return false
        }
        if event.keyCode == shortcuts.code(for: .original) { forceOriginal(); return true }
        if event.keyCode == shortcuts.code(for: .hangul) { forceHangul(); return true }
        switch event.keyCode {
        case 53: // Escape explicitly chooses the original keys.
            if !raw.isEmpty || !words.isEmpty { commitRaw(); return true }
            return false
        case 51:
            if event.modifierFlags.contains(.option) { return deleteWord() }
            return backspace()
        case 36, 76:
            do {
                try commitForReturn()
                lastCommit = nil
                feedback = nil
                trackHostInsertion("\n")
                // The host receives the original Return, including its Shift modifier.
                return false
            } catch {
                report(error)
                return true
            }
        case 48: // Tab ends the composition immediately before host focus navigation.
            commitHangul()
            return false
        case 123...126: // Navigation belongs to the host after ending the current composition.
            commitHangul()
            return false
        default: break
        }
        guard let characters = event.characters, !characters.isEmpty else { return false }
        if characters.unicodeScalars.allSatisfy({ (65...90).contains($0.value) || (97...122).contains($0.value) }) {
            if raw.isEmpty && words.isEmpty {
                // Own commits already contain the context, even when the host cannot return it.
                if contextSelection != client.selectedRange() { context = precedingText() }
                lastCommit = nil
            }
            feedback = nil
            if raw.isEmpty, CompositionPreviewSettings.alternateEnabled(in: previewDefaults) {
                onPreviewStart?()
            }
            raw += characters
            render()
            return true
        }
        // Numbers and punctuation delimit the alphabetic word, and retain their original text.
        if !raw.isEmpty || !words.isEmpty { return boundary(characters) }
        if appendToLastConversion(characters) { return true }
        trackHostInsertion(characters)
        return false
    }

    /// Immediate host commits preserve the Hangul composition shown to the user.
    func commitPending() {
        if !rawText.isEmpty { commitHangul() }
    }

    func belongsTo(_ client: any IMKTextInput) -> Bool {
        (self.client as AnyObject) === (client as AnyObject)
    }

    func resume() {
        active = true
        logDiagnostic("session_resumed")
    }

    func suspend() {
        commitPending()
        onPreview?(nil)
        active = false
        feedback = nil
        logDiagnostic("session_suspended")
    }

    func deactivate() {
        commitPending()
        onPreview?(nil)
        active = false
        lastCommit = nil
        feedback = nil
        logDiagnostic("session_deactivated")
    }

    func commitRaw() {
        logDiagnostic("commit_raw_before_clear")
        let text = rawText
        cancelRequest()
        words.removeAll()
        raw = ""
        onPreview?(nil)
        if !text.isEmpty {
            client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        lastCommit = nil
        feedback = nil
        AppSupport.shared.clearError()
    }

    func commitHangul() {
        if lastCommit != nil || !rawText.isEmpty { logDiagnostic("commit_hangul_before_clear") }
        do {
            let text = try previewText()
            cancelRequest()
            words.removeAll()
            raw = ""
            onPreview?(nil)
            if !text.isEmpty {
                client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            lastCommit = nil
            feedback = nil
            AppSupport.shared.clearError()
        } catch { report(error) }
    }

    func forceOriginal() { forceCommit(asHangul: false) }
    func forceHangul() { forceCommit(asHangul: true) }

    /// Keep the exact model/correction result when reversing a completed word twice.
    func toggleLanguage() {
        logDiagnostic("toggle_begin")
        do {
            try finishPendingForShortcut(preservePreview: true)
            guard let previous = lastCommit else {
                logDiagnostic("toggle_no_recent_conversion")
                return
            }
            logDiagnostic("toggle_target_ready")
            try validateFeedback(Feedback(conversionID: previous.id, raw: previous.raw, before: previous.before,
                                          rejected: previous.selected, separator: previous.separator,
                                          range: previous.range, expectedText: previous.text, source: previous.source))
            let alternate = try previous.languageAlternative ??
                (previous.selected == previous.raw ? HangulComposer.compose(previous.raw) : previous.raw)
            let conversion = Conversion(id: previous.id, raw: previous.raw, selected: alternate, separator: previous.separator,
                                        before: previous.before,
                                        range: NSRange(location: previous.range.location,
                                                       length: (alternate + previous.separator).utf16.count),
                                        languageAlternative: previous.selected, source: .languageShortcut)
            client.insertText(conversion.text, replacementRange: previous.range)
            context = String((conversion.before + conversion.text).suffix(120))
            contextSelection = client.selectedRange()
            lastCommit = conversion
            feedback = nil
            AppSupport.shared.clearError()
            logDiagnostic("toggle_complete")
        } catch {
            logFailure(error, stage: "toggle_failed")
            let failure = error as NSError
            logger.error("Language toggle failed: \(failure.domain, privacy: .public) code \(failure.code)")
            onError("방금 입력한 단어를 바꾸지 못했습니다. 입력 위치를 확인해 주세요.")
        }
    }

    func completeForCorrection() throws {
        logDiagnostic("correction_prepare_begin")
        try finishPendingForShortcut(preservePreview: false)
    }

    private func finishPendingForShortcut(preservePreview: Bool) throws {
        guard !rawText.isEmpty else { return }
        cancelRequest()
        // Earlier queued words retain their model decisions even during rapid typing.
        while let word = words.first {
            let before = context
            let selected = try ReturnDecision.resolve(decision(for: word.raw, before: before))
            try commitFirstWord(selected, before: before)
        }
        if !raw.isEmpty {
            let keys = raw
            words.append(Word(raw: keys, separator: ""))
            raw = ""
            render()
            let before = context
            let selected = try preservePreview ? preview(keys) :
                ReturnDecision.resolve(decision(for: keys, before: before))
            try commitFirstWord(selected, before: before, source: preservePreview ? .inlinePreview : .automaticOrMemory)
        }
    }

    /// Explicit language keys can also change the word immediately before the caret.
    /// Host navigation and session shutdown continue to commit only pending composition.
    private func forceCommit(asHangul: Bool) {
        logger.notice("Language shortcut received; Hangul=\(asHangul) pending=\(!self.rawText.isEmpty) recent=\(self.lastCommit != nil)")
        do {
            func selected(_ keys: String) throws -> String {
                asHangul ? try HangulComposer.compose(keys) : keys
            }
            let conversion: Conversion
            if !raw.isEmpty || !words.isEmpty {
                let range = client.markedRange()
                guard active, range.location != NSNotFound else {
                    throw SessionError("The host lost the marked composition before a language shortcut.")
                }
                var pending = words
                if !raw.isEmpty { pending.append(Word(raw: raw, separator: "")) }
                let last = pending.removeLast()
                let prefix = try pending.map { try selected($0.raw) + $0.separator }.joined()
                let before = String((context + prefix).suffix(120))
                let text = try selected(last.raw)
                conversion = Conversion(id: last.id, raw: last.raw, selected: text, separator: last.separator,
                                        before: before,
                                        range: NSRange(location: range.location + prefix.utf16.count,
                                                       length: (text + last.separator).utf16.count), source: .languageShortcut)
                cancelRequest()
                words.removeAll()
                raw = ""
                onPreview?(nil)
                client.insertText(prefix + conversion.text, replacementRange: range)
            } else if let previous = lastCommit {
                try validateFeedback(Feedback(conversionID: previous.id, raw: previous.raw, before: previous.before,
                                              rejected: previous.selected, separator: previous.separator,
                                              range: previous.range, expectedText: previous.text, source: previous.source))
                let text = try selected(previous.raw)
                conversion = Conversion(id: previous.id, raw: previous.raw, selected: text, separator: previous.separator,
                                        before: previous.before,
                                        range: NSRange(location: previous.range.location,
                                                       length: (text + previous.separator).utf16.count), source: .languageShortcut)
                cancelRequest()
                client.insertText(conversion.text, replacementRange: previous.range)
            } else {
                return
            }
            context = String((conversion.before + conversion.text).suffix(120))
            contextSelection = client.selectedRange()
            lastCommit = conversion
            feedback = nil
            AppSupport.shared.clearError()
        } catch {
            let failure = error as NSError
            logger.error("Language shortcut failed: \(failure.domain, privacy: .public) code \(failure.code)")
            onError("방금 입력한 단어를 바꾸지 못했습니다. 입력 위치를 확인해 주세요.")
        }
    }

    private var rawText: String {
        words.map { $0.raw + $0.separator }.joined() + raw
    }

    private func preview(_ keys: String) throws -> String {
        CompositionPreviewSettings.english(for: hostBundleID, in: previewDefaults)
            ? keys : try HangulComposer.compose(keys)
    }

    private func previewText() throws -> String {
        try words.map { word in
            (word.raw.isEmpty ? "" : try preview(word.raw)) + word.separator
        }.joined() + (raw.isEmpty ? "" : try preview(raw))
    }

    private func render(replacementRange: NSRange = NSRange(location: NSNotFound, length: 0)) {
        do {
            // A paragraph break is committed separately; marking it can replace a host paragraph.
            let text = try previewText().replacingOccurrences(of: "\n", with: "")
            client.setMarkedText(text,
                                 selectionRange: NSRange(location: text.utf16.count, length: 0),
                                 replacementRange: replacementRange)
            if let onPreview {
                // Only the word still being typed belongs in the alternate preview.
                let alternate = raw.isEmpty || !CompositionPreviewSettings.alternateEnabled(in: previewDefaults) ? nil :
                    (CompositionPreviewSettings.english(for: hostBundleID, in: previewDefaults)
                        ? try HangulComposer.compose(raw) : raw)
                onPreview(alternate)
            }
        } catch { report(error) }
    }

    private func boundary(_ separator: String) -> Bool {
        guard !raw.isEmpty || !words.isEmpty else { return false }
        feedback = nil
        if raw.isEmpty {
            words[words.count - 1].separator += separator
        } else {
            words.append(Word(raw: raw, separator: separator))
            raw = ""
        }
        render()
        beginRequest()
        return true
    }

    private func commitForReturn() throws {
        cancelRequest()
        if !raw.isEmpty {
            words.append(Word(raw: raw, separator: ""))
            raw = ""
            render()
        }
        while let word = words.first {
            let before = context
            let select = try decision(for: word.raw, before: before)
            let selected = try ReturnDecision.resolve(select)
            try commitFirstWord(selected, before: before)
        }
    }

    private func appendToLastConversion(_ suffix: String) -> Bool {
        guard var commit = lastCommit else { return false }
        guard commit.range.location != NSNotFound,
              client.selectedRange() == NSRange(location: commit.range.location + commit.range.length, length: 0) else {
            lastCommit = nil
            return false
        }
        client.insertText(suffix, replacementRange: NSRange(location: NSNotFound, length: 0))
        commit.separator += suffix
        commit.range.length += suffix.utf16.count
        lastCommit = commit
        context = String((commit.before + commit.text).suffix(120))
        contextSelection = client.selectedRange()
        feedback = nil
        return true
    }

    private func trackHostInsertion(_ text: String) {
        let caret = client.selectedRange()
        if contextSelection == caret, caret.length == 0, caret.location != NSNotFound {
            context = String((context + text).suffix(120))
            contextSelection = NSRange(location: caret.location + text.utf16.count, length: 0)
        }
    }

    private func backspace() -> Bool {
        if !raw.isEmpty {
            feedback = nil
            raw.removeLast()
            render()
            return true
        }
        if let word = words.last {
            if !word.separator.isEmpty {
                words[words.count - 1].separator.removeLast()
                render()
                return true
            }
            cancelRequest()
            words.removeLast()
            raw = word.raw
            raw.removeLast()
            render()
            beginRequest()
            return true
        }
        if contextSelection == client.selectedRange(), let last = context.last {
            context.removeLast()
            let caret = client.selectedRange()
            contextSelection = NSRange(location: max(0, caret.location - String(last).utf16.count), length: 0)
        }
        lastCommit = nil
        feedback = nil
        return false
    }

    private func deleteWord() -> Bool {
        lastCommit = nil
        feedback = nil
        if !raw.isEmpty {
            raw = ""
            render()
            return true
        }
        guard !words.isEmpty else { return false }
        cancelRequest()
        while let word = words.popLast() {
            if !word.raw.isEmpty { break }
        }
        render()
        beginRequest()
        return true
    }

    var feedbackAvailable: Bool {
        active && words.isEmpty && raw.isEmpty && lastCommit != nil
    }

    func prepareFeedback() throws -> [Candidate] {
        guard feedbackAvailable else {
            logDiagnostic("correction_not_available")
            throw SessionError("No completed word is available for correction.")
        }
        let target: Feedback
        if let commit = lastCommit {
            target = Feedback(conversionID: commit.id, raw: commit.raw, before: commit.before, rejected: commit.selected,
                              separator: commit.separator, range: commit.range, expectedText: commit.text, source: commit.source)
        } else {
            throw SessionError("The last conversion is no longer available.")
        }
        try validateFeedback(target)
        let candidates = try CandidateBuilder.candidates(for: target.raw, includeSplits: true)
        feedback = target
        return candidates
    }

    func cancelFeedback() {
        feedback = nil
    }

    func feedbackDisplayText(for candidate: Candidate) throws -> String {
        guard let feedback else {
            throw SessionError("No correction is being selected.")
        }
        return candidate.text + feedback.separator
    }

    func applyFeedback(preferred: String, scope: CorrectionScope) async throws {
        guard let target = feedback else {
            throw SessionError("No correction is being selected.")
        }
        try validateFeedback(target)
        try corrections.record(raw: target.raw, before: target.before, rejected: target.rejected,
                               preferred: preferred, scope: scope)
        let text = preferred + target.separator
        cancelRequest()
        words.removeAll()
        raw = ""
        onPreview?(nil)
        client.insertText(text, replacementRange: target.range)
        context = String((target.before + text).suffix(120))
        lastCommit = Conversion(id: target.conversionID, raw: target.raw, selected: preferred, separator: target.separator,
                                before: target.before,
                                range: NSRange(location: target.range.location, length: text.utf16.count), source: .correction)
        contextSelection = client.selectedRange()
        feedback = nil
        AppSupport.shared.clearError()
        logger.notice("User correction saved")
        let candidates = try CandidateBuilder.candidates(for: target.raw, includeSplits: true)
        let local = try localClient ?? LocalModelService.client()
        _ = try await local.correct(raw: target.raw, before: target.before,
                                    candidates: candidates, preferred: preferred, scope: scope)
    }

    private func validateFeedback(_ target: Feedback) throws {
        let selection = client.selectedRange()
        guard active, words.isEmpty, target.range.location != NSNotFound,
              selection == NSRange(location: target.range.location + target.range.length, length: 0) else {
            let reason = !active ? "session_inactive" : !words.isEmpty ? "pending_words" :
                target.range.location == NSNotFound ? "target_range_missing" : "caret_mismatch"
            diagnosticLogger.error("Validation rejected; session=\(self.diagnosticID, privacy: .public) reason=\(reason, privacy: .public) target=\(NSStringFromRange(target.range), privacy: .public) selection=\(NSStringFromRange(selection), privacy: .public)")
            throw SessionError("The cursor moved away from the conversion.")
        }
        var actualRange = NSRange(location: NSNotFound, length: 0)
        let hostText = client.string(from: target.range, actualRange: &actualRange)
        guard let text = hostText,
              actualRange == target.range, text == target.expectedText else {
            let reason = hostText == nil ? "host_text_unavailable" :
                actualRange != target.range ? "host_range_mismatch" : "host_text_mismatch"
            diagnosticLogger.error("Validation rejected; session=\(self.diagnosticID, privacy: .public) reason=\(reason, privacy: .public) target=\(NSStringFromRange(target.range), privacy: .public) returnedRange=\(NSStringFromRange(actualRange), privacy: .public) returnedUTF16=\(hostText?.utf16.count ?? -1) expectedUTF16=\(target.expectedText.utf16.count) textMatches=\(hostText == target.expectedText)")
            throw SessionError("The converted text changed before correction.")
        }
    }

    private func beginRequest() {
        guard active, task == nil, !words.isEmpty else { return }
        let epoch = generation
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.active, self.generation == epoch, let word = self.words.first {
                do {
                    let before = self.context
                    let select = try self.decision(for: word.raw, before: before)
                    let selected = try await select()
                    guard self.active, self.generation == epoch, self.words.first?.id == word.id else { return }
                    try self.commitFirstWord(selected, before: before)
                    let englishPrefixLength = selected.prefix(while: { $0.isASCII }).count
                    self.logger.info("Word decided locally; keys=\(word.raw.count) context=\(before.count) English-prefix=\(englishPrefixLength)")
                } catch {
                    guard self.active, self.generation == epoch else { return }
                    self.report(error)
                    self.task = nil
                    return
                }
            }
            if self.generation == epoch { self.task = nil }
        }
    }

    private func decision(for raw: String, before: String) throws -> (@Sendable () async throws -> String) {
        guard !raw.isEmpty else { return { "" } }
        let candidates = try CandidateBuilder.candidates(for: raw, includeSplits: true)
        let memory = try corrections.load()
        if let preferred = memory.preferred(raw: raw, before: before) {
            let rememberedCandidates = try CandidateBuilder.candidates(for: raw, includeSplits: true)
            guard rememberedCandidates.contains(where: { $0.text == preferred }) else {
                throw SessionError("The saved correction is not a valid candidate.")
            }
            return { preferred }
        }
        let local = try localClient ?? LocalModelService.client()
        return { try await local.decide(raw: raw, before: before, candidates: candidates).predicted }
    }

    private func commitFirstWord(_ selected: String, before: String,
                                 source: SelectionSource = .automaticOrMemory) throws {
        let range = client.markedRange()
        guard range.location != NSNotFound else {
            logDiagnostic("commit_marked_range_missing")
            throw SessionError("The host lost the marked composition before commitment.")
        }
        let word = words.removeFirst()
        let text = selected + word.separator
        // One host update commits the word and separator together, including during fast typing.
        client.insertText(text, replacementRange: range)
        context = String((context + text).suffix(120))
        let selection = client.selectedRange()
        contextSelection = selection
        // Commitment has already succeeded. Hosts without a document insertion point
        // cannot provide a safe target for subsequent edits; do not retain a stale target.
        lastCommit = nil
        feedback = nil
        if selection.location != NSNotFound, selection.length == 0,
           selection.location >= text.utf16.count {
            // The host may rebase its text storage while ending marked composition.
            // Track the inserted text in the post-commit coordinate space used by selectedRange/string(from:).
            let committedRange = NSRange(location: selection.location - text.utf16.count, length: text.utf16.count)
            if committedRange != NSRange(location: range.location, length: text.utf16.count) {
                diagnosticLogger.notice("Commit coordinates changed; session=\(self.diagnosticID, privacy: .public) markedBefore=\(NSStringFromRange(range), privacy: .public) selectionAfter=\(NSStringFromRange(selection), privacy: .public) committedRange=\(NSStringFromRange(committedRange), privacy: .public)")
            }
            lastCommit = Conversion(id: word.id, raw: word.raw, selected: selected, separator: word.separator, before: before,
                                    range: committedRange, source: source)
        } else {
            logDiagnostic("commit_complete_without_edit_target")
        }
        if !rawText.isEmpty { render() }
        AppSupport.shared.clearError()
    }

    private func cancelRequest() {
        generation += 1
        task?.cancel()
        task = nil
    }

    private func precedingText() -> String {
        let selected = client.selectedRange()
        let marked = client.markedRange()
        let end = marked.location == NSNotFound ? selected.location : marked.location
        guard end != NSNotFound, end > 0 else { return "" }
        let range = NSRange(location: max(0, end - 120), length: min(120, end))
        var actualRange = NSRange(location: NSNotFound, length: 0)
        let text = client.string(from: range, actualRange: &actualRange)
        return text?.precomposedStringWithCanonicalMapping ?? ""
    }


    private func report(_ error: Error) {
        onPreview?(nil)
        logFailure(error, stage: "composition_failed")
        // Log status/type without sending private typed text or response bodies to diagnostics.
        let failure = error as NSError
        logger.error("Decision failed: \(failure.domain, privacy: .public) code \(failure.code)")
        onError("판별하지 못했습니다. Space로 다시 시도하거나 Esc로 원문을 확정하세요.")
    }

    // Metadata only: never include raw input, converted text, context, or correction candidates.
    func logDiagnostic(_ stage: String) {
        let selection = client.selectedRange()
        let marked = client.markedRange()
        diagnosticLogger.notice("Session state; session=\(self.diagnosticID, privacy: .public) stage=\(stage, privacy: .public) active=\(self.active) queued=\(self.words.count) rawUTF16=\(self.raw.utf16.count) task=\(self.task != nil) generation=\(self.generation) recent=\(self.lastCommit != nil) selection=\(NSStringFromRange(selection), privacy: .public) marked=\(NSStringFromRange(marked), privacy: .public) recentRange=\(String(describing: self.lastCommit?.range), privacy: .public)")
    }

    func logFailure(_ error: Error, stage: String) {
        // SessionError details are fixed strings in this file; other error payloads stay private.
        if let failure = error as? SessionError {
            diagnosticLogger.error("Session failure; session=\(self.diagnosticID, privacy: .public) stage=\(stage, privacy: .public) detail=\(failure.detail, privacy: .public)")
        } else {
            let failure = error as NSError
            diagnosticLogger.error("Session failure; session=\(self.diagnosticID, privacy: .public) stage=\(stage, privacy: .public) domain=\(failure.domain, privacy: .public) code=\(failure.code)")
        }
        logDiagnostic(stage)
    }
}

private final class ReturnDecision: @unchecked Sendable {
    private let ready = DispatchSemaphore(value: 0)
    private var result: Result<String, Error>?

    static func resolve(_ select: @escaping @Sendable () async throws -> String) throws -> String {
        let completion = ReturnDecision()
        // IMK's synchronous event handler must finish commitment before returning false.
        Task.detached(priority: .userInitiated) {
            do { completion.result = .success(try await select()) }
            catch { completion.result = .failure(error) }
            completion.ready.signal()
        }
        let started = DispatchTime.now()
        completion.ready.wait()
        let milliseconds = (DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        if milliseconds > 300 {
            Logger(subsystem: "com.yeop.inputmethod.JevType", category: "Shortcuts")
                .notice("Return decision blocked main thread; ms=\(milliseconds)")
        }
        return try completion.result!.get()
    }
}

private struct SessionError: LocalizedError {
    let detail: String
    init(_ detail: String) { self.detail = detail }
    var errorDescription: String? { detail }
}
