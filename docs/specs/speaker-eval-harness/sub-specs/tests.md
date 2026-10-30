# Tests Specification

This is the tests coverage details for the spec detailed in docs/specs/speaker-eval-harness/spec.md

> Created: 2026-10-29
> Version: 1.0.0

## Test Coverage

The scoring and labeling logic is pure and is tested without audio models. Only `run` against real audio is a manual check.

### Unit Tests

**Scorer**
- Line fully inside one labeled interval gets that speaker as truth.
- Line split 60/40 between two speakers gets the 60% speaker; split with both over 30% is marked overlap.
- Line inside `nonMemberSpans` is non-member; a Guest attribution there is correct, a member attribution is wrong.
- Unflagged error rate counts only wrong lines with `needsReview == false`, and excludes nothing else.
- Flag recall is 1.0 when every wrong line is flagged, and handles zero wrong lines without dividing by zero.
- Review burden: 10 flagged lines of 5 s each in a 10-minute meeting gives (50 + 40) / 600 * 3600 / 60 = 9.0 minutes per hour.
- Pooling by line count differs from pooling by duration on a crafted two-session fixture.
- Confusion matrix rows sum to the line counts per true speaker.

**LabelGenerator**
- Two synthetic sine-burst tracks with known on/off times produce intervals within one frame of truth.
- A track offset of 0.42 s shifts its intervals by 0.42 s.
- Bleed: a quiet copy of speaker A's burst in B's track does not create a B interval.
- Simultaneous loud bursts in both tracks produce overlapping intervals.
- Clap sync proposes the correct offset for a synthetic clap at known positions.

**Report**
- Same inputs produce byte-identical JSON; keys are sorted.
- `compare` shows zero deltas for identical reports and signed deltas otherwise.

**VoiceTuning**
- `VoiceTuning()` equals today's constants (0.40, 0.50, 0.06, 0.10).

### Integration Tests

**CLI argument handling**
- `run` with a missing `labels.json` exits non-zero with a message naming the session.
- `--sure-similarity` overrides the default and is recorded in the report's tuning block.

**Engine unchanged by default**
- On one short fixture recording, `process` with `VoiceTuning()` returns lines identical to the pre-change engine (snapshot taken before the refactor).

### Manual Verification

- Stage the pub session; run `label`, listen to 20 random intervals, expect at least 19 correct.
- `run` twice; reports identical. Change `--sure-similarity` to 0.60; flagged rate rises.
- Listen to every wrong-and-unflagged line in the report to confirm the labels, not the engine, are at fault or not.

### Mocking Requirements

- **VoiceEngine:** scorer tests feed hand-built `ProcessedLine` arrays; no FluidAudio needed.
- **Audio:** synthetic sine bursts generated in test code, no recorded fixtures committed.
- **Time/clock:** none; nothing in the harness depends on the current time except a timestamp in the report, which is injected.
