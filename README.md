# Minits

Record a board meeting or an ad-hoc meeting on one iPhone (or Mac), find out who said what, and get draft minutes or a summary. Everything runs on the device: the recording, each member's voiceprint, the transcript and the minutes or summary never leave it.

## How it works

1. **Pick the kind of meeting on Home.** Two cream keys under START A MEETING: *Board meeting* gets formal minutes; *Ad-hoc meeting* gets a plain summary. Each shows what you get and an example line. The one you used last is lit with SK-1's orange bar. Tapping a key opens roll call with that kind selected; you can still switch it there.
2. **Voice roll call.** Each member says one sentence (about 10 seconds). [FluidAudio](https://github.com/FluidInference/FluidAudio) turns it into a voiceprint, saved for future meetings. Optional in an ad-hoc meeting: saved members start as not here, and anyone without a voice shows as Guest 1, Guest 2…
3. **Record.** One tap. Keeps recording with the screen locked. The recording screen has one big LCD: a red REC lamp that blinks while recording ("PAUSED" when paused), the kind of meeting and how many are here, the elapsed time in seven-segment digits and the input level. Under it, three keys: **Pause/Resume**, the orange **Mark motion** key (board meeting: tap it when someone makes a motion or the board votes) or **Mark moment** (ad-hoc meeting: tap it when something is decided), and the charcoal **End** key with a red lamp, which asks before it stops. Each mark shows as a chip such as `MOTION 1 · 12:04` in the tray above the keys. If a call or another app interrupts, the recording pauses and an amber lamp says so; tap Resume to keep going.
4. **Who said what.** After the meeting, FluidAudio splits the recording by voice, matches each voice to a saved voiceprint, and transcribes it (Parakeet, English).
5. **Review.** Lines the app isn't sure about are flagged. Play the line, tap the right name. Unknown voices show as Guest 1, Guest 2… and can be named once for all their lines.
6. **Minutes or summary.** On iOS 26 / macOS 26 with Apple Intelligence, the write-up is drafted on-device:
   - *Board meeting:* formal minutes (attendance, discussion, motions with mover/seconder/vote, action items).
   - *Ad-hoc meeting:* a summary (what it was about, topics discussed, decisions, action items, open questions).

   Without Apple Intelligence you get an outline built from the transcript instead: likely decisions and action items pulled out by phrases like "agreed" or "I'll", each marked spot quoted, and (for ad-hoc meetings) the full transcript.

The voice and transcription models download once on first use (a few hundred MB, Wi-Fi recommended). After that the app works offline.

## Look

Minits uses the SK-1 look (cream chassis, sunken trays, raised keys, olive LCD, orange only for the main action) from [SK1Kit](https://github.com/jsonify/SK1Kit), a Swift package shared with Skreener (`SK1Tokens` and `SK1UI`, version 0.2.0 or later). It follows the system's Light or Dark Mode. The Home and recording screens are built from SK1Kit's components; the other screens are moving over one at a time and meanwhile use `UI/Theme.swift`, a temporary bridge that maps their colours to SK-1 tokens.

## Build it (Mac, free Apple ID is fine)

Requirements: a Mac with Xcode 16 or newer (Xcode 26 to get the Apple Intelligence minutes), and [Homebrew](https://brew.sh).

```bash
brew install xcodegen
git clone https://github.com/jsonify/Minits.git
cd Minits
xcodegen
open Minits.xcodeproj
```

In Xcode:

1. Select the **Minits** target → **Signing & Capabilities** → **Team** → add your Apple ID and pick your Personal Team.
   If Xcode says the bundle ID is taken, change `com.jsonify.minits` to something unique.
2. **Mac:** choose *My Mac* as the run destination and press ⌘R. A Mac build doesn't expire.
3. **iPhone:** plug it in, choose it as the destination, press ⌘R.
   - First time: on the iPhone, turn on **Settings › Privacy & Security › Developer Mode**, then trust your profile in **Settings › General › VPN & Device Management**.
   - With a free Apple ID the iPhone app stops opening after **7 days**. Plug in and press ⌘R again to renew it; your saved voices and meetings stay.

When `project.yml` changes, run `xcodegen` again. Xcode fetches the Swift packages (FluidAudio, SK1Kit) on first build.

## Project layout

```
project.yml                 XcodeGen spec (one app target for iOS 17+ and macOS 14+; packages FluidAudio, SK1Kit)
.github/workflows/ci.yml    CI: builds the app for iOS and macOS and runs MinitsEvalTests on every push and PR
Minits/
  MinitsApp.swift           App entry, navigation
  Models/Models.swift       SwiftData: Member, Meeting, TranscriptLine
  Audio/                    16 kHz mono WAV recorder, clip playback
  Voice/VoiceEngine.swift   FluidAudio: voiceprints, diarization, matching, transcription
  Minutes/MinutesWriter.swift  Minutes (board) or summary (ad-hoc): Apple Intelligence draft, or outline fallback
  UI/                       Screens (home, roll call, recording, review, transcript, minutes/summary)
  UI/Theme.swift            Temporary bridge from the old colours to SK-1 tokens, removed once every screen uses SK1Kit
  Eval/                     Speaker-attribution scoring and labeling (not part of the app; used by tests and the eval tool)
Tools/minits-eval/          `minits-eval` command-line tool (macOS): check, label, spotcheck, run, compare
Tests/MinitsEvalTests/      Unit tests for Eval/ (run on a Mac, no iPhone needed, no FluidAudio)
Tests/MinitsTests/          Tests for Voice/ and Minutes/ (VoiceTuning, a VoiceEngine snapshot test, the outline fallback; needs FluidAudio + a Mac)
docs/specs/                 Feature specs
```

## Tests

```bash
xcodegen
xcodebuild test -scheme MinitsEvalTests -destination 'platform=macOS'
xcodebuild test -scheme MinitsTests -destination 'platform=macOS'
```

CI (GitHub Actions, `macos-latest`) runs `xcodegen`, builds the `Minits` scheme for the iOS Simulator and for macOS without signing, runs `MinitsEvalTests`, and lists compiler warnings in `Minits/UI` and `MinitsApp.swift` in the run summary (it fails on warnings in the files already on SK-1). It doesn't run `MinitsTests`, which needs the models.

`MinitsTests` downloads FluidAudio's models on first run and needs a Mac with a Neural Engine (Apple Silicon) — the ASR model crashes on Intel Macs.

## Tuning

Voice-matching thresholds live in `VoiceTuning` at the top of `VoiceEngine.swift` and default to today's hand-picked values (`VoiceEngine.shared` always uses the defaults). Raise `sureSimilarity` to flag more lines for review; lower it to flag fewer. The eval harness (`docs/specs/speaker-eval-harness/`) overrides these per run instead of editing code.

## Measuring speaker attribution

`minits-eval` scores `VoiceEngine` against labeled sessions in `eval/` (audio is git-ignored; see the spec for the folder layout). To record a session, follow [`docs/specs/speaker-eval-harness/recording-guide.md`](docs/specs/speaker-eval-harness/recording-guide.md).

```bash
xcodebuild -scheme minits-eval build
minits-eval check eval/2026-11-02-pub            # missing/misnamed files, unconverted .m4a, short samples, no clap
minits-eval label eval/2026-11-02-pub            # labels.json from tracks/<member>.wav (clap-synced)
minits-eval spotcheck eval/2026-11-02-pub        # 20 clips + checklist to verify labels by ear (aim for 19/20)
minits-eval run eval/ --out before.json          # per-session and overall metrics
minits-eval run eval/ --sure-similarity 0.55 --out after.json
minits-eval compare before.json after.json
```

## Tips for good results

- Put the phone in the middle of the table. For a big room, a USB or Lightning conference mic helps a lot.
- Record voice samples with the phone about where it will sit during the meeting.
- Let everyone know the meeting is being recorded (California and some other states require everyone's consent).

## Not yet

- Live transcript while recording (the transcript is made after the meeting ends).
- PDF export (Share → Print → save as PDF works in the meantime).
