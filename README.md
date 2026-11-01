# Minits

Record a board meeting or an ad-hoc meeting on one iPhone (or Mac), find out who said what, and get draft minutes or a summary. Everything runs on the device: the recording, each member's voiceprint, the transcript and the minutes or summary never leave it.

## How it works

**First run.** A fresh install opens with a one-time intro, full screen on iPhone and as a sheet on Mac. It has a WELCOME LCD, the three steps (record, who said what, minutes or a summary) as numbered trays, a teal *On this device* note, an amber *Before you record* reminder to tell everyone they're being recorded, and the microphone's state as a lamp. The orange **Allow microphone** key asks for the mic once, then becomes **Get started**; **Not now** skips asking, and roll call asks later instead. If the mic is off, a red lamp says where to turn it on, and on iPhone an **Open Settings** key goes there. The intro doesn't come back after that. Anyone updating from a version without it (members or meetings already saved) never sees it. To see it again, delete and reinstall the app.

1. **Pick the kind of meeting on Home.** Two cream keys under START A MEETING: *Board meeting* gets formal minutes; *Ad-hoc meeting* gets a plain summary. Each shows what you get and an example line. The one you used last is lit with SK-1's orange bar. Tapping a key opens roll call with that kind selected; you can still switch it there.
2. **Voice roll call.** Roll call shows an LCD with how many are here and how many of them have a voice saved, then the members as rows in one tray: tap a row to mark someone here or not (an indicator square shows which), touch and hold (right-click on Mac) to **Edit…**, re-record or remove. **Edit…** opens the member sheet with their name and role filled in; their saved voice stays. If you change the name, a **Rename in past transcripts** toggle (off by default) also renames every line already marked as them. Minutes and summaries already written keep the old name until you redraft. Each member keeps their avatar colour: a new member gets the first colour nobody has, and removing someone doesn't recolour the rest. A teal lamp means the voice is saved; otherwise the row has a **Record** key. **Add member or guest** opens a sheet with LCD text fields for the name and an optional role; once added, their voice sample starts. The meeting name is an LCD text field too, and the orange **Start meeting** key sits at the bottom. Each member says one sentence (about 10 seconds). [FluidAudio](https://github.com/FluidInference/FluidAudio) turns it into a voiceprint, saved for future meetings. The voice sample sheet works like the recording screen: an LCD with a status lamp, the member's name and role, the elapsed time and the input level, the line to read in a tray, and the orange **Record** key. **Stop** (charcoal, red lamp) works after 4 seconds and stops on its own at 15. If the new voice sounds a lot like another member's, an amber lamp says so. Optional in an ad-hoc meeting: saved members start as not here, and anyone without a voice shows as Guest 1, Guest 2…
3. **Record.** One tap. Keeps recording with the screen locked. The recording screen has one big LCD: a red REC lamp that blinks while recording ("PAUSED" when paused), the kind of meeting and how many are here, the elapsed time in seven-segment digits and the input level. Under it, three keys: **Pause/Resume**, the orange **Mark motion** key (board meeting: tap it when someone makes a motion or the board votes) or **Mark moment** (ad-hoc meeting: tap it when something is decided), and the charcoal **End** key with a red lamp, which asks before it stops. Each mark shows as a chip such as `MOTION 1 · 12:04` in the tray above the keys. If a call or another app interrupts, the recording pauses and an amber lamp says so; tap Resume to keep going.

   **On the lock screen (iPhone).** While it records, a Live Activity shows on the lock screen and in the Dynamic Island. On the lock screen it's an olive LCD with the red REC lamp (PAUSED or INTERRUPTED when paused), the kind of meeting and how many are here, the elapsed time, how many motions or moments are marked and the meeting's name, with a **Pause/Resume** key and the orange **Mark motion** (or **Mark moment**) key under it. Both keys work without unlocking. The Dynamic Island shows the lamp and the time; touch and hold it for the keys. Tap anywhere else to open Minits. It goes away when the meeting ends, and at the next launch if the app was closed mid-meeting. Turn it off in Settings › Minits › Live Activities.
4. **Who said what.** After the meeting, FluidAudio splits the recording by voice, matches each voice to a saved voiceprint, and transcribes it (Parakeet, English). While it works, an LCD shows a blinking WORKING lamp, the current step, how far along it is as a percentage and a bar of cells. If it fails, a red lamp shows the error and the orange **Try again** key starts over; the recording is kept. When it's done, a segmented control switches between **Review** (with how many lines need a look, e.g. `REVIEW · 3`), **Transcript** and **Minutes** or **Summary**.
5. **Review.** Lines the app isn't sure about are flagged. An LCD shows how many are left to check. Each line is a tray with the speaker, its time on an LCD chip and a play key; a flagged line has an amber lamp with the reason and its choices as keys, the current guess lit with the orange bar. Play the line, tap the right name, or **Someone else…** for the full list. Unknown voices show as Guest 1, Guest 2… and can be named once for all their lines. The Transcript tab shows every line, with a **Motions only** toggle and a **Share** key, under a cassette deck that plays the whole meeting (see **Transcript playback**).
6. **Minutes or summary.** On iOS 26 / macOS 26 with Apple Intelligence, the write-up is drafted on-device:
   - *Board meeting:* formal minutes (attendance, discussion, motions with mover/seconder/vote, action items).
   - *Ad-hoc meeting:* a summary (what it was about, topics discussed, decisions, action items, open questions).

   Without Apple Intelligence you get an outline built from the transcript instead: likely decisions and action items pulled out by phrases like "agreed" or "I'll", each marked spot quoted, and (for ad-hoc meetings) the full transcript.

   The orange key drafts it, with an LCD readout of what it's doing; lines still to check get an amber note first. The draft is editable in a tray under a teal DRAFT lamp, with **Redraft** (asks first), **Copy**, **PDF** and the orange **Share** key. If drafting fails you get the outline, with the error shown above it.

   **PDF** makes a plain, printable PDF (black on white, not the SK-1 look) named after the meeting, e.g. `October Board Meeting.pdf`: the meeting's title and date, for a board meeting the attendance (members here and absent, with their roles), then the minutes or summary as edited, with Markdown headings (`#`, `**Bold line**`, ALL-CAPS lines and the section names the drafts use) and bulleted or numbered lists kept, and *Page 1 of 3* at the foot of each page. Pages break between lines and never end on a heading. Paper is US Letter in regions that use US measurements, A4 elsewhere. On iPhone it opens the share sheet (Save to Files, Mail, AirDrop, Print…); on Mac it opens a save panel. It's made on the device, with no network.

**Transcript playback.** The Transcript tab has a 1970s-style cassette deck pinned above the lines. The meeting is a cassette in a smoky window, between the VOLUME and SPEED knobs, with its title and date handwritten on the index label, SIDE A and a tape length (C30 to C120, the shortest the meeting fits on one side of). While it plays, the reels turn and the tape winds from the left reel to the right, so you can see how far in you are. With Reduce Motion the reels stay still, but the tape still moves across. The **VOLUME** knob (0 to 10) sits to the left of the cassette and the **SPEED** knob (0.75×, 1×, 1.25×, 1.5×, 2×) to the right. Drag up or down to turn a knob; with VoiceOver, swipe up or down. Under the cassette:
- Two backlit VU meters. Recordings are mono, so they show **AVG** (average level) and **PEAK**; a stereo file would show LEFT and RIGHT.
- Piano keys: **STOP** (stops and rewinds to the start), **◀◀** and **▶▶** (10 seconds back or forward), **PLAY** and **PAUSE**. PLAY and PAUSE stay down while they're on.
- A tape counter showing the position and the length.

The line being played has a lit orange lamp, and the list scrolls to follow it. A line's play key plays the deck from just before that line; tap it again to pause. The deck stops when you leave the tab. The Review tab still plays one line at a time.

**Renaming or deleting a meeting.** On a meeting's screen, the **Edit** menu (top right) has **Rename…** and **Delete meeting…**. On Home, touch and hold (right-click on Mac) a past meeting for the same two. Rename opens an LCD text field. Delete asks first, then removes the recording, transcript and write-up from the device; from the meeting's screen it also goes back to Home. Neither is offered while a meeting is recording or processing.

The voice and transcription models download once on first use (a few hundred MB, Wi-Fi recommended). After that the app works offline. Until they're on the device, Home shows a **One-time setup** tray with a **Download now** key. While it downloads, an LCD there shows a blinking DOWNLOADING lamp, which model and step it's on (e.g. `TRANSCRIPTION MODEL · FILE 3 OF 5`, then `SETTING UP TRANSCRIPTION MODEL`), how far along the whole download is as a percentage, and a bar of cells. On iPhone the screen stays on until it's done. If it fails, a red lamp shows why and the key reads **Try again**.

## Look

Minits uses the SK-1 look (cream chassis, sunken trays, raised keys, olive LCD, orange only for the main action) from [SK1Kit](https://github.com/jsonify/SK1Kit), a Swift package shared with Skreener (`SK1Tokens` and `SK1UI`, version 0.3.0 or later). It follows the system's Light or Dark Mode. Every screen is built from SK1Kit's components. The only colours of Minits' own are the member avatars (SK-1 has none for people), in `UI/Shared.swift`, and the transcript's cassette deck (`UI/CassetteDeck.swift`): the cassette and the warm VU meter faces are drawn as physical objects, so they look the same in Light and Dark Mode, apart from the meters' backlight dimming as the LCD's does. The deck's knobs use SK1Kit's knob maths (`SK1.KnobScale`).

**App icon.** The icon is the transcript deck's cassette on the cream chassis: smoky window and reels, a handwritten index label with SIDE A, and SK-1's orange band. On iOS 18 and later it has a Dark Mode version on the charcoal chassis, which the home screen uses when it's set to dark icons. The Mac icon follows the macOS icon grid (a rounded square with a margin and shadow). It's drawn as SVG by `Tools/app-icon/make_icon.py` from SK1Kit's and the cassette's colours, and `Tools/app-icon/render.js` renders the PNGs in `Minits/Assets.xcassets/AppIcon.appiconset` (needs Python 3, Node and Playwright with Chromium):

```bash
python3 Tools/app-icon/make_icon.py && node Tools/app-icon/render.js
```

## Build it (Mac, free Apple ID is fine)

Requirements: a Mac with Xcode 16 or newer (Xcode 26 to get the Apple Intelligence minutes), and [Homebrew](https://brew.sh).

```bash
brew install xcodegen
git clone https://github.com/jsonify/Minits.git
cd Minits
git config core.hooksPath .githooks   # once per clone: regenerate the project after every pull (see below)
xcodegen
open Minits.xcodeproj
```

In Xcode:

1. **Signing.** Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and fill in your Team ID and a bundle ID your team owns (`com.jsonify.minits` is taken). Run `xcodegen` again. The Live Activity extension uses the same team and your bundle ID plus `.recording`, so there's nothing more to set. `Local.xcconfig` is gitignored and survives every `xcodegen` run, so you set this once. (Picking a team in **Signing & Capabilities** also works, but `xcodegen` resets it.) Your Team ID is under Xcode › Settings › Accounts, or Membership details on developer.apple.com. A free Personal Team works too.
2. **Mac:** choose *My Mac* as the run destination and press ⌘R. A Mac build doesn't expire.
3. **iPhone:** plug it in, choose it as the destination, press ⌘R.
   - First time: on the iPhone, turn on **Settings › Privacy & Security › Developer Mode**, then trust your profile in **Settings › General › VPN & Device Management**.
   - With a free Apple ID the iPhone app stops opening after **7 days**. Plug in and press ⌘R again to renew it; your saved voices and meetings stay.

**Keep the project current after every `git pull`.** `Minits.xcodeproj` is generated, not committed, so an old copy doesn't know about new packages or files. With the hooks turned on (`git config core.hooksPath .githooks`, once per clone), git runs `xcodegen` for you after `git pull`, `git merge`, switching branches and `git rebase`, including when you pull from Xcode. If Xcode is open, it reloads the project. Without the hooks, run `xcodegen` yourself after every pull. If `xcodegen` isn't installed, the hook says so and the pull still goes through. Check whether the hooks are on with `git config core.hooksPath` (it prints `.githooks`).

If you skip the regenerate, the build fails. It fails with *Unable to resolve module dependency: 'SK1Tokens'*, or, after a file was removed or added, *Build input file cannot be found: '…/Minits/UI/Theme.swift'*. Xcode fetches the Swift packages (FluidAudio, SK1Kit) on the first build after that. When `project.yml` raises a package's version and Xcode keeps the old one (for example *Cannot find 'SKTextField' in scope* while SK1Kit still shows 0.2.0 under Package Dependencies), use **File › Packages › Update to Latest Package Versions**; if it still can't resolve them, use **File › Packages › Reset Package Caches**.

## Project layout

```
project.yml                 XcodeGen spec (one app target for iOS 17+ and macOS 14+, the iOS Live Activity extension; packages FluidAudio, SK1Kit)
Config/Signing.xcconfig     App bundle ID and team defaults; includes your gitignored Config/Local.xcconfig
.githooks/                  Git hooks that run xcodegen after a pull, merge, branch switch or rebase (turn on: git config core.hooksPath .githooks)
.github/workflows/ci.yml    CI: builds the app for iOS and macOS and runs MinitsEvalTests on every push and PR
Minits/
  MinitsApp.swift           App entry, navigation
  Models/Models.swift       SwiftData: Member, Meeting, TranscriptLine
  Audio/                    16 kHz mono WAV recorder, clip playback
  Audio/MeetingPlayer.swift Whole-meeting playback for the cassette deck: transport, volume, speed, meters, current line
  Voice/VoiceEngine.swift   FluidAudio: voiceprints, diarization, matching, transcription
  Minutes/MinutesWriter.swift  Minutes (board) or summary (ad-hoc): Apple Intelligence draft, or outline fallback
  Export/MinutesPDF.swift   The minutes or summary as a printable PDF (Core Text; reads the draft's Markdown, paginates)
  LiveActivity/             The recording's Live Activity: its attributes and Pause/Mark intents (shared with the extension), and starting/updating/ending it
MinitsRecordingWidget/      Widget extension (iOS): draws the recording's Live Activity on the lock screen and in the Dynamic Island
  UI/                       Screens (home, roll call, recording, review, transcript, minutes/summary)
  UI/MeetingTitleSheet.swift Rename a meeting (from Home and the meeting screen)
  UI/CassetteDeck.swift     The transcript's cassette deck: cassette and reels, VU meters, knobs, piano-key transport, counter
  UI/IntroView.swift        The first-run intro: how it works, on this device, the consent reminder, the microphone
  UI/Shared.swift           Member avatars, the app's SK-1 ink tint, and the iPhone inline title
  Assets.xcassets/AppIcon.appiconset  The app icon: iOS light and dark (1024 px), Mac at every size
  Eval/                     Speaker-attribution scoring and labeling (not part of the app; used by tests and the eval tool)
Tools/app-icon/             Draws the app icon (make_icon.py) and renders it into Minits/Assets.xcassets/AppIcon.appiconset (render.js)
Tools/minits-eval/          `minits-eval` command-line tool (macOS): check, label, spotcheck, run, compare
Tests/MinitsEvalTests/      Unit tests for Eval/ (run on a Mac, no iPhone needed, no FluidAudio)
Tests/MinitsTests/          Tests for Voice/ and Minutes/ (VoiceTuning, model download progress, a VoiceEngine snapshot test, the outline fallback; needs FluidAudio + a Mac)
Tests/MinitsScreenTests/    Screenshots of every screen from sample data (ScreenFixtures.swift), and tests of member and meeting edits and the PDF export; run on the iOS Simulator
docs/specs/                 Feature specs
```

## Tests

```bash
xcodegen
xcodebuild test -scheme MinitsEvalTests -destination 'platform=macOS'
xcodebuild test -scheme MinitsTests -destination 'platform=macOS'
MINITS_SNAPSHOT_DIR=/tmp/minits-screens xcodebuild test -scheme MinitsScreenTests -destination 'platform=iOS Simulator,name=iPhone 16'
```

CI (GitHub Actions, `macos-latest`) runs `xcodegen`, builds the `Minits` scheme for the iOS Simulator and for macOS without signing, runs `MinitsEvalTests` and `MinitsScreenTests`, and lists compiler warnings in `Minits/UI` and `MinitsApp.swift` in the run summary (any warning there fails the run). It doesn't run `MinitsTests`, which needs the models.

### Screenshots

`MinitsScreenTests` renders every screen from sample data: Home (empty and with meetings), roll call (board and ad-hoc), Add member, the voice sample, recording, processing, a failed meeting, Review, the transcript (with the cassette deck at rest), the cassette deck mid-meeting while it plays, a summary not yet written, finished minutes, the Edit member and Rename meeting sheets, Home's model download tray (downloading, and failed), and the first-run intro (before the mic is asked, and with the mic off). Each one is rendered in light and dark, at an iPhone width (390 pt) and a wide window's (720 pt, about the Mac's). The screens are shown without starting the mic or the models. It checks that each screen renders, not that it matches a saved image.

- **On a PR:** open the CI run's Summary page and download the `minits-screens` artifact (PNGs at 2x, named like `10-review-iphone-dark.png`).
- **Locally:** run the command above. With `MINITS_SNAPSHOT_DIR` set (on the command line, as `TEST_RUNNER_MINITS_SNAPSHOT_DIR`, or in the scheme's environment) the PNGs are written there. Either way they're attached to the test results in Xcode's Report navigator.
- **The sample data** is in `Tests/MinitsScreenTests/ScreenFixtures.swift`. Add a state there and a line in `ScreenSnapshotTests.swift` when a screen gains one.

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
