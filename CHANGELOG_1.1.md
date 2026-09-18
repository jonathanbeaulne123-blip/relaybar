# RelayBar 1.1.0 — Prove It (Claim Ledger)

Release 1.1.0 (Build 21) — September 18, 2026.

Every packet, checkpoint and handoff RelayBar has ever produced carries the same
line: *UNVERIFIED unless evidence is attached.* Until now that was a promise the
user could not keep — nothing in RelayBar knew which sentences were checkable,
and nothing could settle them.

1.1.0 makes the promise earned. RelayBar extracts every falsifiable assertion
from the text you are about to send, settles each one against a bounded local
read or a command **you declared**, and stamps an evidence receipt into the
handoff. It then runs the same extractor over the assistant's reply and flags
any statement the receipt does not support.

Nothing about this runs on a server. There is no model call, no network access
and no telemetry: extraction is deterministic pattern matching over the text,
and every verdict is either an observation RelayBar made locally or a command it
ran on your machine.

---

## What's new in 1.1.0

### 1. Claim extraction (`ClaimExtractor.swift`, `ClaimLedger.swift`)

* **Ten claim kinds.** `testsPass`, `buildSucceeds`, `lintClean`, `fileExists`,
  `lineContains`, `symbolDefined`, `referenceCount`, `gitFact`, `assertion`, and
  `notFalsifiable` for proposals, opinions and hedged suggestions ("we should
  probably revisit this"). Hedging, proposals and questions are never checkable.
* **Polarity is per rule, not per regex.** "No longer exists", "was removed" and
  "doesn't exist" are the *negative* form of the same claim, so a refutation of
  one can never be read as confirmation of the other.
* **The stored sentence is verbatim.** A separate display projection strips
  control, zero-width and bidirectional-override characters, so a receipt cannot
  be made to *look* like it says something it does not.
* **Bounded and disclosed.** Fenced code blocks are excluded; the first 400
  characters of the reviewed text are kept as the audit trail; at most 24 claims
  are extracted. The ledger records how many statements it did **not** recognize
  (`unmatchedSentenceCount`) and whether a cap was reached (`truncated`), and the
  receipt prints both. Unrecognized text never silently becomes "verified".

### 2. Local observations (`ClaimObservation.swift`)

* File existence with a SHA-256 fingerprint of the bytes it read.
* Line-text reads (`path:line`) that report a missing file rather than an empty
  line.
* Symbol definitions and references from a bounded scan — 4,000 files, 1 MB per
  file, 50 hits — that reports truncation instead of guessing.
* Git facts read with the *same* porcelain-v2 parser the live Git monitor uses
  (`GitMonitor.record(fromPorcelainV2:commit:)`), so the ledger and the status
  indicator cannot disagree about whether the tree is clean.
* Every probe is read-only. Reads are confined to the project root; a path that
  escapes it is refused, not resolved.

### 3. Declared verify commands (`VerifyCommand.swift`)

* A command is an **intent** (`tests`, `build`, `lint`) plus a shell string the
  user typed. RelayBar never derives a command from prose — not from the
  reviewed text, not from a claim, not from a suggestion.
* 5–1800 second timeout, project-scoped, at most 20 declarations, each with a
  name, working-directory choice and budget. Validation rejects duplicates and
  oversized values at the model layer.
* If two declared commands could settle the same kind, the ledger refuses to
  guess and says which ones are ambiguous.
* Declared commands appear in the Command Palette like any other command, but
  they are only ever started through the ledger's planning rules.

### 4. Verdicts that cannot overstate (`ClaimChecker.swift`, `ClaimReceipt.swift`)

* `✅ verified`, `❌ refuted`, `⚠️ unverified`, `⏭ not checkable`.
* A claim may only be `verified` **if it carries evidence**: `Claim.validate()`
  refuses to persist a verified claim without it, so promotion is impossible by
  construction rather than by convention.
* **Staleness.** A ledger records its base commit. If the repository moves, every
  settled claim is marked stale and reads as `unverified` again, with the receipt
  saying so. A verified claim describes one commit and its observation time.
* **Receipts** list every verdict with its method, SHA-256 prefix, exit code,
  duration and observation time, then state what the receipt does **not**
  establish: unmatched statements, excluded code fences, caps reached, stale
  claims, and — when nothing verified — that nothing verified.
* **Reply audit.** `ClaimMatcher` compares a pasted reply against the saved
  ledger and reports statements the receipt left unverified or refuted. It
  re-runs nothing. Matching is deliberately conservative: same claim kind, same
  stated numbers (word numbers normalized, so "two callers" never matches "three
  callers"), at least two shared content words, and a similarity score that
  accounts for a claim restated *inside* a longer sentence ("the test suite
  passes, so I merged it"). A false accusation costs more than a missed
  reminder, and the audit summary says plainly that it is a comparison against
  RelayBar's own receipt, not a judgement about the reply's author.

### 5. Rehearsal (`GitWorktree.swift`)

Running a declared command on a dirty tree could touch uncommitted work, so on a
dirty tree RelayBar rehearses it in a throwaway Git worktree forked from the
recorded base commit:

* The declared command runs verbatim; only its working directory changes.
* The source worktree is never reset, stashed or overwritten.
* The rehearsal worktree is removed afterwards, or kept on request so you can
  inspect it.
* If Git refuses (missing repository, existing destination, destination inside
  the source, invalid branch), the claim stays `unverified` and the receipt says
  why. RelayBar does not fall back to running it in place.
* Worktrees are never left behind: quitting the app discards an active rehearsal.

### 6. Surfaces

* **New `Verify` page** under `Context` on the Touch Bar: `Verify`, `Audit reply`,
  `Receipt`, `Ledger ›`.
* **One evidence chip** (`🔎 3✓ 1⚠ 2↻`) that fits beside the fixed shell controls
  on every page without crowding it, and switches to `❗ n repeated` when the
  reply audit has findings.
* **Native Claim Ledger panel** — verdict rows with their evidence, the complete
  receipt preview, a *Keep the rehearsal worktree* switch, *Declare verify
  command…*, and *Back to work*.
* **Menu and palette** — Review the draft as claims, Audit reply, Claim ledger,
  Declare verify command…; `RB → Verify` submenu; declared commands searchable.
* **Journal** — `claimLedgerCreated`, `claimVerified`, `rehearsalRan`,
  `claimRepeated`, and two new session-packet counters ("Claims Verified /
  Refuted", "Reply Claims the Receipt Did Not Support").
* **Packets** — every generated prompt now carries an evidence receipt block, or
  states that no ledger was attached and therefore nothing in it is locally
  verified.
* **Storage** — ledgers are written to the private `Ledgers` directory with the
  same atomic JSON and `0700`/`0600` permissions as checkpoints. Ledgers are
  never pruned automatically.

### 7. Boundaries this feature keeps

* Only declared commands execute. Ambiguity produces a refusal, not a best guess.
* One command at a time, cancellable; `RelayBar` never runs a second concurrently.
* The project root comes from the reality timeline's project or the focused
  app's working directory. It is never inferred from the reviewed text. Without a
  root, the review is refused.
* The clipboard is written only when you ask (receipt or audit), the receipt is
  marked as RelayBar output so the Context Stack will not collect it back as
  yours, and RelayBar never pastes or sends.
* `NSPasteboard.general` is not read or written by the feature; the native
  self-test asserts that.

---

## Files

Added (Core):

| File | Contents |
|---|---|
| `Sources/Core/ClaimLedger.swift` | `Claim`, `ClaimKind`, `ClaimSource`, `ClaimPolarity`, `ClaimVerdict`, `ClaimProbe`, `ClaimEvidence`, `ClaimLedger`, `LedgerSummary`, `LedgerPolicy` |
| `Sources/Core/ClaimExtractor.swift` | Deterministic extraction of falsifiable claims from reviewed text |
| `Sources/Core/ClaimObservation.swift` | `ClaimObservationSource`, `SystemClaimObservationSource`, `ClaimObserver`, `ClaimPathGuard`, `ScanHit` |
| `Sources/Core/ClaimChecker.swift` | `ClaimEnvironment`, `ClaimTask`, planning, verdict application, staleness |
| `Sources/Core/ClaimReceipt.swift` | `ClaimReceiptRenderer`, `ClaimMatcher`, `ReplyAuditFinding`, `LedgerChip` |
| `Sources/Core/VerifyCommand.swift` | `VerifyCommandKind`, `VerifyCommand`, `VerifyCommandLibrary` |
| `Sources/Core/GitWorktree.swift` | `GitWorktree`, `RehearsalWorktreePlan`, `RehearsalWorktree`, `RehearsalError` |

Added (macOS):

| File | Contents |
|---|---|
| `Sources/Mac/ClaimLedgerMac.swift` | `ClaimLedgerController`, ledger panel, declared-command editor, chip and page slots |
| `Sources/Mac/ClaimLedgerNativeChecks.swift` | Hermetic native self-test (another pasteboard, synthetic observation source, no command executed) |

Added (tests): `Tests/RelayCoreTests/ClaimExtractorTests.swift`,
`ClaimCheckerTests.swift`, `ClaimReceiptTests.swift`,
`RehearsalWorktreeTests.swift`.

Changed:

* `Sources/Core/Models.swift` — `Configuration.verifyCommands` (capped, unique,
  validated); `Equatable` conformances required by `RealitySnapshot`.
* `Sources/Core/LocalStore.swift` — `Ledgers` directory, `saveLedger`,
  `loadLedger`, `listLedgers`.
* `Sources/Core/SessionJournal.swift` — four ledger entry kinds and two packet
  counters.
* `Sources/Core/PromptEngine.swift` — every generated packet carries the evidence
  receipt (or declares that none was attached).
* `Sources/Core/ButtonHierarchy.swift` — the `Verify` page and its four commands.
* `Sources/Core/CommandIndex.swift` — declared verify commands are searchable.
* `Sources/Core/GitMonitor.swift` — shared porcelain-v2 interpretation; the
  indicator no longer shows a clean tree when no repository was found.
* `Sources/Mac/AppMain.swift` — controller wiring, menu items, `Verify` page and
  chip, `--claim-ledger-self-test`, diagnostics version.
* `Run_Self_Test.command` — `claim-ledger` suite, included in `all`.
* `Install.command` — accepts an installed 1.0.0/1.1.0 build when upgrading.
* `Tests/RelayCoreTests/ButtonHierarchyTests.swift` — the Context page now owns
  the Verify page.
* `Resources/Info.plist` — 1.1.0, build 21.

---

## Unchanged & preserved

Everything RelayBar already did is untouched with its existing guarantees: the
persistent Touch Bar shell and Apple handoff, Verified Click for
Sheets/Hearth Tools, adaptive menu scanning, Menu Cascade, Screenshot Shelf,
Button Families, Context Stack, Pinned Chats, Fork Reality, Project/Briefs
tooling, and local-only storage with zero network calls.

No browser extension, no Apps Script, no API key, no network request, and no
model call was added.

See `Docs/VALIDATION_1.1.md` for exactly what was executed, what it proves, and
what remains unverified.
