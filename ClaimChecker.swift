import Foundation

/// The observed state a ledger is checked against. Everything here is read
/// only: the single mutation in this feature is a declared command run, and
/// only the controller is allowed to start one.
public struct ClaimEnvironment: Equatable {
    public let gitRoot: String
    public let commit: String
    public let tree: GitSnapshotRecord
    public let verifyCommands: [VerifyCommand]
    public let projectID: String

    public init(gitRoot: String, commit: String, tree: GitSnapshotRecord, verifyCommands: [VerifyCommand], projectID: String) {
        self.gitRoot = gitRoot
        self.commit = commit
        self.tree = tree
        self.verifyCommands = verifyCommands
        self.projectID = projectID
    }

    public func command(for kind: VerifyCommandKind) -> VerifyCommand? {
        VerifyCommandLibrary.command(for: kind, in: verifyCommands, projectID: projectID)
    }

    public func ambiguity(for kind: VerifyCommandKind) -> String? {
        VerifyCommandLibrary.ambiguityDescription(for: kind, in: verifyCommands, projectID: projectID)
    }
}

/// What RelayBar intends to do about one claim. Planning is pure: it decides
/// isolation and refuses what it cannot run, but it never executes anything.
public enum ClaimTask: Equatable {
    case observe(claimID: UUID, probe: ClaimProbe)
    case execute(claimID: UUID, command: VerifyCommand, rehearsal: RehearsalWorktreePlan?)
    case skip(claimID: UUID, verdict: ClaimVerdict, note: String)

    public var claimID: UUID {
        switch self {
        case .observe(let id, _): return id
        case .execute(let id, _, _): return id
        case .skip(let id, _, _): return id
        }
    }
}

/// Turns observations and declared command results into verdicts.
///
/// Every rule here exists to make "verified" hard to reach: a bounded scan can
/// prove presence but never absence, a missing file is a refutation rather than
/// an error, and a probe that could not run is UNVERIFIED no matter what the
/// claim asserted.
public final class ClaimChecker {
    private let observer: ClaimObserver

    public init(observer: ClaimObserver = ClaimObserver()) {
        self.observer = observer
    }

    // MARK: Ledger construction

    public func makeLedger(
        text: String,
        source: ClaimSource,
        environment: ClaimEnvironment,
        projectName: String
    ) throws -> ClaimLedger {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClaimLedgerError.emptySource }
        let extraction = ClaimExtractor.extract(from: text, source: source)
        guard !extraction.oversized else { throw ClaimLedgerError.oversizedSource }

        let claims = extraction.claims.map { original -> Claim in
            var claim = original
            switch claim.strategy {
            case .impossible(let reason):
                claim.verdict = .notCheckable
                claim.note = reason
            case .observe, .execute:
                claim.verdict = .unverified
                claim.note = "Reviewed but not checked yet."
            }
            return claim
        }

        let ledger = ClaimLedger(
            projectID: environment.projectID,
            projectName: projectName,
            gitRoot: environment.gitRoot,
            baseCommit: environment.commit,
            treeState: environment.tree,
            source: source,
            sourcePreview: LedgerPolicy.displayText(text, limit: LedgerPolicy.maxClaimCharacters),
            claims: claims,
            unmatchedSentenceCount: extraction.unmatchedSentenceCount,
            excludedCodeFenceLines: extraction.excludedCodeFenceLines,
            truncated: extraction.truncated
        )
        try ledger.validate()
        return ledger
    }

    // MARK: Planning

    /// One task per included claim, in review order. Nothing is executed here;
    /// a clean tree runs in place, and a dirty tree is isolated in a rehearsal
    /// worktree so uncommitted work can never be an experiment's casualty.
    public func plan(_ ledger: ClaimLedger, environment: ClaimEnvironment) -> [ClaimTask] {
        ledger.claims.filter(\.included).map { claim in
            switch claim.strategy {
            case .impossible(let reason):
                return .skip(claimID: claim.id, verdict: .notCheckable, note: reason)

            case .observe(let probe):
                return .observe(claimID: claim.id, probe: probe)

            case .execute(let kind):
                guard let command = environment.command(for: kind) else {
                    if let ambiguity = environment.ambiguity(for: kind) {
                        return .skip(claimID: claim.id, verdict: .unverified, note: ambiguity)
                    }
                    return .skip(claimID: claim.id, verdict: .unverified,
                                 note: "No \(kind.declaredNoun) is declared for this project, so nothing was executed. Declare one in Settings to let RelayBar settle this claim.")
                }
                guard !environment.commit.isEmpty else {
                    return .skip(claimID: claim.id, verdict: .unverified,
                                 note: "RelayBar could not read the current commit, so this check could not be reproduced. Nothing was executed.")
                }
                guard environment.tree.isDirty else {
                    return .execute(claimID: claim.id, command: command, rehearsal: nil)
                }
                do {
                    let rehearsal = try RehearsalWorktree().plan(
                        sourceRoot: environment.gitRoot,
                        baseCommit: environment.commit,
                        ledgerID: ledger.id
                    )
                    return .execute(claimID: claim.id, command: command, rehearsal: rehearsal)
                } catch {
                    return .skip(claimID: claim.id, verdict: .unverified,
                                 note: "This project has uncommitted changes, so RelayBar would only run the declared command inside a throwaway worktree — and it could not prepare one. Nothing was executed. \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: Applying results

    /// Escapes an excerpt bound without pretending the text ended there.
    public static func boundedExcerpt(_ text: String, limit: Int = LedgerPolicy.maxExcerptCharacters) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n… [relaybar excerpt cut at \(limit) characters; the complete output was hashed but not stored]"
    }

    public func apply(_ result: ClaimProbeResult, to claim: Claim, baseCommit: String, observedAt: Date = Date()) -> Claim {
        var claim = claim

        // A probe that could not run settles nothing. Checked first so no later
        // case can accidentally promote it.
        if case .unavailable(let reason) = result {
            claim.verdict = .unverified
            claim.note = reason
            claim.evidence = nil
            return claim
        }

        switch (claim.strategy, result) {
        case (.observe(.fileExists), .fileExistence(let relative, let exists, let hash)):
            let met = claim.polarity == .affirmative ? exists : !exists
            claim.verdict = met ? .verified : .refuted
            claim.note = exists
                ? "\(relative) is present in this working tree."
                : "\(relative) is not present in this working tree."
            claim.evidence = ClaimEvidence(method: "Path existence", summary: claim.note, excerpt: relative,
                                           contentHash: hash, baseCommit: baseCommit, observedAt: observedAt)

        case (.observe(.lineContains(_, _, let needle)), .line(let relative, let observedLine, let text, let fileMissing, let hash)):
            let location = "\(relative):\(observedLine)"
            if let text = text {
                let contentMatches = !needle.isEmpty && text.contains(needle)
                let isEmpty = text.trimmingCharacters(in: .whitespaces).isEmpty
                let met: Bool
                if needle.isEmpty {
                    met = !isEmpty
                    claim.note = met
                        ? "\(location) exists and is not empty. No specific text was asserted, so this is a weaker check."
                        : "\(location) exists but is empty, so no content could be confirmed there."
                } else {
                    met = claim.polarity == .affirmative ? contentMatches : !contentMatches
                    claim.note = contentMatches
                        ? "\(location) contains \"\(needle)\" (case-sensitive)."
                        : "\(location) does not contain \"\(needle)\" (case-sensitive)."
                }
                claim.verdict = met ? .verified : .refuted
                claim.evidence = ClaimEvidence(method: "Read line \(observedLine)", summary: claim.note,
                                               excerpt: Self.boundedExcerpt(text, limit: 1_000), contentHash: hash,
                                               baseCommit: baseCommit, observedAt: observedAt)
            } else {
                claim.verdict = .refuted
                claim.note = fileMissing
                    ? "\(relative) does not exist, so \(location) could not be read."
                    : "\(relative) has no line \(observedLine) in the version RelayBar read."
                claim.evidence = ClaimEvidence(method: "Read line \(observedLine)", summary: claim.note,
                                               contentHash: hash, baseCommit: baseCommit, observedAt: observedAt)
            }

        case (.observe(.symbolDefined), .symbol(let name, let definitions, let references, let truncated)):
            let found = !definitions.isEmpty
            let met = claim.polarity == .affirmative ? found : !found
            claim.verdict = met ? .verified : .refuted
            claim.note = found
                ? "\(name) is declared at \(definitions.count) place(s): \(definitions.prefix(LedgerPolicy.maxRenderedHits).map(\.display).joined(separator: ", "))."
                : "No declaration of \(name) was found in the scanned files."
            if truncated && !found {
                claim.verdict = .unverified
                claim.note = "RelayBar's scan stopped at its own file or hit bound before finishing, so the absence of \(name) could not be confirmed. No conclusion was drawn."
            }
            claim.evidence = ClaimEvidence(method: "Project scan (whole-word, bounded)", summary: claim.note,
                                           excerpt: rendered(definitions + references), contentHash: hitsHash(definitions, references),
                                           baseCommit: baseCommit, observedAt: observedAt)

        case (.observe(.referenceCount(let name, let expected)), .symbol(let symbol, let definitions, let references, let truncated)):
            let count = references.count
            let met = expected.matches(count)
            claim.verdict = met ? .verified : .refuted
            claim.note = "\(name): \(count) reference(s) outside its declaration line(s); expected \(expected.title)."
            if truncated && !met {
                claim.verdict = .unverified
                claim.note = "RelayBar's scan stopped at its own bound after \(count) reference(s) to \(symbol), so the reference count could not be confirmed. No conclusion was drawn."
            }
            claim.evidence = ClaimEvidence(method: "Project scan (whole-word, bounded)", summary: claim.note,
                                           excerpt: rendered(references), contentHash: hitsHash(definitions, references),
                                           baseCommit: baseCommit, observedAt: observedAt)

        case (.observe(.gitFact(let expectation)), .git(let snapshot)):
            let actual: GitFactExpectation = snapshot.isDirty ? .dirty : .clean
            claim.verdict = actual == expectation ? .verified : .refuted
            claim.note = "Working tree is \(actual.title) (branch \(snapshot.branch.isEmpty ? "unknown" : snapshot.branch), \(snapshot.modifiedCount) modified, \(snapshot.stagedCount) staged, \(snapshot.untrackedCount) untracked)."
            claim.evidence = ClaimEvidence(method: "Read Git state",
                                           summary: claim.note,
                                           excerpt: "branch \(snapshot.branch)\nmodified \(snapshot.modifiedCount)\nstaged \(snapshot.stagedCount)\nuntracked \(snapshot.untrackedCount)",
                                           contentHash: SHA256Digest.hex(claim.note),
                                           baseCommit: baseCommit, observedAt: observedAt)

        default:
            claim.verdict = .unverified
            claim.note = "RelayBar had no matching observation for this claim. Nothing was concluded."
            claim.evidence = nil
        }
        return claim
    }

    /// Applies a declared command's result. A cancelled or timed-out run
    /// concludes nothing, and negative claims ("the tests do not pass") are
    /// settled by a non-zero exit rather than being inverted by guesswork.
    public func apply(
        _ result: ActionResult,
        to claim: Claim,
        command: VerifyCommand,
        baseCommit: String,
        worktree: String?
    ) -> Claim {
        var claim = claim
        let kind = claim.kind.verifyCommandKind
        let noun = kind?.declaredNoun ?? "verification command"
        let location = worktree == nil ? "at the project root" : "inside a throwaway rehearsal worktree"

        if result.exitCode < 0 || result.exitCode > 128 {
            claim.verdict = .unverified
            claim.note = "The declared \(noun) was cancelled, timed out, or ended without an exit status, so RelayBar concluded nothing. Your project was not changed by this check."
            claim.evidence = ClaimEvidence(method: "Ran the declared \(noun)", commandLine: command.command,
                                           summary: claim.note, excerpt: Self.boundedExcerpt(result.output),
                                           contentHash: SHA256Digest.hex(result.output), exitCode: result.exitCode,
                                           durationSeconds: result.duration, worktreePath: worktree,
                                           baseCommit: baseCommit)
            return claim
        }

        let succeeded = result.exitCode == 0
        let met = claim.polarity == .affirmative ? succeeded : !succeeded
        claim.verdict = met ? .verified : .refuted
        claim.note = "The declared \(noun) `\(command.command)` exited \(result.exitCode) in \(String(format: "%.1f", result.duration))s \(location)."
        claim.evidence = ClaimEvidence(method: "Ran the declared \(noun)", commandLine: command.command,
                                       summary: claim.note, excerpt: Self.boundedExcerpt(result.output),
                                       contentHash: SHA256Digest.hex(result.output), exitCode: result.exitCode,
                                       durationSeconds: result.duration, worktreePath: worktree,
                                       baseCommit: baseCommit)
        return claim
    }

    public func applySkip(_ task: ClaimTask, to ledger: ClaimLedger) -> ClaimLedger {
        guard case .skip(let claimID, let verdict, let note) = task, let claim = ledger.claim(id: claimID) else { return ledger }
        var updated = claim
        updated.verdict = verdict
        updated.note = note
        if verdict == .notCheckable { updated.evidence = nil }
        return replace(ledger, with: updated)
    }

    public func replace(_ ledger: ClaimLedger, with claim: Claim) -> ClaimLedger {
        guard let index = ledger.claims.firstIndex(where: { $0.id == claim.id }) else { return ledger }
        var copy = ledger
        copy.claims[index] = claim
        copy.revision = UUID()
        return copy
    }

    /// Marks settled observations stale when the repository has moved since the
    /// ledger was created, so a receipt never presents an old read as current.
    public func staled(_ ledger: ClaimLedger, environment: ClaimEnvironment) -> ClaimLedger {
        ledger.staled(against: environment.commit)
    }

    private func rendered(_ hits: [ScanHit]) -> String {
        guard !hits.isEmpty else { return "" }
        let shown = hits.prefix(LedgerPolicy.maxRenderedHits).map { "\($0.display)  \($0.text)" }.joined(separator: "\n")
        return hits.count > LedgerPolicy.maxRenderedHits ? shown + "\n… and \(hits.count - LedgerPolicy.maxRenderedHits) more" : shown
    }

    private func hitsHash(_ definitions: [ScanHit], _ references: [ScanHit]) -> String {
        let joined = (definitions + references).sorted().map { "\($0.relativePath):\($0.line):\($0.text)" }.joined(separator: "\n")
        return joined.isEmpty ? SHA256Digest.hex("no-hits") : SHA256Digest.hex(joined)
    }
}
