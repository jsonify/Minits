# Minits

Record a board meeting on one iPhone (or Mac), find out who said what, and get draft minutes. Everything runs on the device: the recording, each member's voiceprint, the transcript and the minutes never leave it.

## How it works

1. **Voice roll call.** Each member says one sentence (about 10 seconds). [FluidAudio](https://github.com/FluidInference/FluidAudio) turns it into a voiceprint, saved for future meetings.
2. **Record.** One tap. Keeps recording with the screen locked. Tap **Mark motion** when someone makes a motion or the board votes.
3. **Who said what.** After the meeting, FluidAudio splits the recording by voice, matches each voice to a saved voiceprint, and transcribes it (Parakeet, English).
4. **Review.** Lines the app isn't sure about are flagged. Play the line, tap the right name. Unknown voices show as Guest 1, Guest 2… and can be named once for all their lines.
5. **Minutes.** On iOS 26 / macOS 26 with Apple Intelligence, the minutes are drafted on-device (attendance, motions with mover/seconder/vote, action items). Otherwise you get an outline with each marked motion quoted from the transcript.

The voice and transcription models download once on first use (a few hundred MB, Wi-Fi recommended). After that the app works offline.

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

When `project.yml` changes, run `xcodegen` again.

## Project layout

```
project.yml                 XcodeGen spec (one app target for iOS 17+ and macOS 14+)
Minits/
  MinitsApp.swift           App entry, navigation
  Models/Models.swift       SwiftData: Member, Meeting, TranscriptLine
  Audio/                    16 kHz mono WAV recorder, clip playback
  Voice/VoiceEngine.swift   FluidAudio: voiceprints, diarization, matching, transcription
  Minutes/MinutesWriter.swift  Apple Intelligence draft, or outline fallback
  UI/                       Screens (roll call, recording, review, transcript, minutes)
  Eval/                     Speaker-attribution scoring and labeling (not part of the app; used by tests and the eval tool)
Tools/minits-eval/          `minits-eval` command-line tool (macOS): label, run, compare
Tests/MinitsEvalTests/      Unit tests for Eval/ (run on a Mac, no iPhone needed, no FluidAudio)
Tests/MinitsTests/          Tests for Voice/ (VoiceTuning, a VoiceEngine snapshot test; needs FluidAudio + a Mac)
docs/specs/                 Feature specs
```

## Tests

```bash
xcodegen
xcodebuild test -scheme MinitsEvalTests -destination 'platform=macOS'
xcodebuild test -scheme MinitsTests -destination 'platform=macOS'
```

`MinitsTests` downloads FluidAudio's models on first run and needs a Mac with a Neural Engine (Apple Silicon) — the ASR model crashes on Intel Macs.

## Tuning

Voice-matching thresholds live in `VoiceTuning` at the top of `VoiceEngine.swift` and default to today's hand-picked values (`VoiceEngine.shared` always uses the defaults). Raise `sureSimilarity` to flag more lines for review; lower it to flag fewer. The eval harness (`docs/specs/speaker-eval-harness/`) overrides these per run instead of editing code.

## Measuring speaker attribution

`minits-eval` scores `VoiceEngine` against labeled sessions in `eval/` (audio is git-ignored; see the spec for the folder layout).

```bash
xcodebuild -scheme minits-eval build
minits-eval label eval/2026-11-02-pub            # labels.json from tracks/<member>.wav (clap-synced)
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
