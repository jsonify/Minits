# Spec Requirements Document

> Spec: Speaker Attribution Evaluation Harness
> Created: 2026-10-29
> Status: Planning

## Overview

Build a macOS command-line tool that runs `VoiceEngine` on labeled meeting recordings and reports how often speakers are attributed correctly, how often wrong attributions slip through unflagged, and how much review a meeting needs. Every later change to speaker identification (background hiding, crosstalk flags, voiceprint adaptation, threshold tuning) is scored against it.

## Why

- Thresholds in `VoiceEngine.swift` (`acceptSimilarity`, `sureSimilarity`, `minimumMargin`, the 0.10 override) are hand-picked. There is no way to tell whether a change helps or hurts.
- Target conditions are a 4-5 member board in a pub, one phone on the table, discussion-heavy.
- Quality bar: reviewing one hour of meeting takes at most 10 minutes, and under 1% of lines are wrongly attributed without a flag. An unflagged wrong name is the worst error.

## User Stories

### Score a change

As the developer, I want to run one command against my recorded sessions and get accuracy, unflagged-error rate and review burden, so that I can accept or reject a change to the matching logic with numbers.

Run `minits-eval run eval/` and read a per-session and overall report. Re-run with `--accept-similarity 0.45` to try a threshold without editing code, and diff two report files.

### Label a session cheaply

As the developer, I want ground-truth labels generated from per-person recordings made on each member's own device during a staged session, so that I don't have to label pub audio by ear.

Each member records themselves while the shared phone records the table. `minits-eval label` turns those clean tracks into `labels.json`. This is a development aid only; the shipped app uses one phone and nothing else.

## Spec Scope

1. **Eval CLI target** - a macOS command-line target `minits-eval` in `project.yml` that links FluidAudio and compiles `VoiceEngine.swift` unchanged apart from the tuning injection below.
2. **Session format and label generator** - a folder layout per session, plus `label` which derives speaker-activity intervals from per-person tracks and a sync offset.
3. **Scoring** - `run` processes each session through `VoiceEngine` and scores every output line against ground truth.
4. **Tuning injection** - `VoiceEngine` thresholds become a `Tuning` value with today's numbers as defaults, so the CLI can override them and the app is unchanged.
5. **Report** - human-readable table plus a JSON file for diffing between runs.

## Out of Scope

- Background-voice hiding, crosstalk flags and voiceprint adaptation (separate specs; this harness exists to evaluate them).
- Transcription accuracy (word error rate). Only who-said-it is scored.
- Running on iOS, or inside the app UI.
- Committing any audio. Recordings stay local.
- Automatic threshold search. The harness measures; a human chooses.

## Expected Deliverable

1. `xcodegen && xcodebuild -scheme minits-eval build` succeeds, and `minits-eval run eval/` on a staged session prints per-session and overall metrics.
2. Running twice with identical inputs gives identical JSON reports; running with a changed threshold flag changes the numbers.
3. The app target still builds and behaves identically with default tuning.
