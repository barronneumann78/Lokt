# Logic checks — the compiled-harness convention

Lokt's XCTest targets are stubs the scheme never builds, so pure logic is
verified with small compiled harnesses instead. Agents have used this pattern
throughout (analytics math 51/51, set-completion 84/84, day scorecard 35/35,
discovery hints 21/21, name-matcher cache 6/6) — but those lived in ephemeral
scratchpads and died with their sessions. **New harnesses belong here instead.**

## Convention

One directory per subject, e.g. `analytics/`, containing:

- `main.swift` — assertions written as plain checks that print `PASS`/`FAIL`
  lines and `exit(1)` on any failure.
- `SOURCES` — a text file listing the REAL app sources to compile against,
  one repo-relative path per line (e.g. `LockIn Set Tracker/AnalyticsModels.swift`).
  Compile against the shipping code, never copies — copies drift.

Run one:

```bash
cd "$(git rev-parse --show-toplevel)"
swiftc -o /tmp/logic-check harness/logic-checks/<name>/main.swift \
  $(cat harness/logic-checks/<name>/SOURCES | sed 's/.*/"&"/' | tr '\n' ' ') \
  && /tmp/logic-check
```

(Quote paths — they contain spaces. Stub any UI-only types the sources drag in
inside `main.swift` rather than importing SwiftUI.)

## Rules

- Deterministic: fixed dates and a fixed timezone in the harness — never `Date()`.
- A harness accompanies any change to: analytics math, set-completion
  semantics, user-memory tiering, name matching, discovery thresholds, or any
  new pure logic worth trusting.
- When a bug is found by hand later, add the reproducing assertion here first,
  then fix.
