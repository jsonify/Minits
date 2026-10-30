# Recording the eval sessions

How to stage and record the two baseline sessions for issue #5: one in a pub, one in a quiet room, with the same 4-5 members. Every later change to speaker attribution is scored against these recordings, so a mistake made here shows up in every result after.

The audio contains real, identifiable voices. It stays on your Mac: `eval/**/*.wav` is git-ignored. Only `session.json`, `labels.json` and `spotcheck/checklist.md` may be committed.

## Before the day

- Tell everyone what's being recorded and why, and that the audio never leaves your Mac. Get their OK to record.
- Settle on one spelling of each member's name, such as `Maria`. File names and `session.json` must use exactly that spelling.
- **Shared phone:** an iPhone with Minits installed and its models downloaded. Turn on airplane mode and Do Not Disturb.
- **Personal devices:** each member records themselves on their own phone with Voice Memos (or a similar app), held in a shirt pocket or placed close in front of them. AirPods work too, as long as the phone records from them. The closer the mic is to each person's mouth, the cleaner the labels.
- Bring a charger. A 20-minute recording is about 40 MB as WAV.

## On the day (do this twice: pub, then quiet room)

1. **Enrollment.** Before the meeting, each member gives a ~10 s sample on the **shared phone**, the way the app takes it: phone about a foot away, saying the app's line ("Hi, I'm Maria, … I'm here for tonight's meeting."). The app doesn't keep its sample file, so record these in Voice Memos on the same phone, one memo per member, named after them.
   In the pub, take the samples at the table, with the pub's noise in the background, just as a real meeting would.
2. **Start every recording.** Put the shared phone in the middle of the table and start recording the meeting in Minits (or in Voice Memos; see "Getting the files off"). Each member starts recording on their own device.
3. **Clap once.** Someone claps once, sharply, loud enough for every device to hear. Then wait 2 seconds. The clap has to be the loudest sound in the first 30 seconds of every recording, so no laughing or banging glasses until after it.
4. **Talk for 15-20 minutes.** Have a real discussion, ideally about something people disagree on: interruptions, crosstalk and short replies are what the eval needs to measure. Have someone make a motion and hold a vote.
5. **Note anyone else who talks.** If a server or someone at the next table speaks clearly, write down roughly when. These spans go into `labels.json` later as `nonMemberSpans`.
6. **Stop everything**, shared phone last.

## Getting the files off

Make one folder per session, named by date and venue:

```
eval/2026-11-02-pub/
  session.json          {"venue": "pub", "members": ["Maria", "Dev", "Sam", "Lee"]}
  table.wav
  enroll/Maria.wav …
  tracks/Maria.wav …
```

- **table.wav:** if you recorded in Minits on the iPhone, open Xcode › Window › Devices and Simulators, select the phone, then Minits › ⋯ › Download Container. The meeting is in `AppData/Library/Application Support/Recordings/<id>.wav`, the newest file. If you recorded in Voice Memos, AirDrop it to the Mac and convert it (below).
- **enroll/ and tracks/:** AirDrop each memo to the Mac and name it after the member.
- **Convert anything that isn't a WAV** to the 16 kHz mono WAV the app records:

  ```bash
  afconvert -f WAVE -d LEI16@16000 -c 1 Maria.m4a Maria.wav
  ```

  Delete the `.m4a` once converted. `check` treats any leftover one as a problem.

## Check, label, spot-check

```bash
xcodebuild -scheme minits-eval build
minits-eval check eval/2026-11-02-pub       # missing or misnamed files, short samples, no clap
minits-eval label eval/2026-11-02-pub       # writes labels.json
minits-eval spotcheck eval/2026-11-02-pub   # 20 clips + spotcheck/checklist.md
```

- `check` exits non-zero on any problem. Fix those first. Warnings (a short table recording, no clap in a track) are worth reading but don't stop you.
- `label` prints each track's offset. Offsets that differ by more than a few seconds between members, or one that's wildly off, mean a clap was missed. Set that member's offset by hand in `session.json` (`"trackOffsetsSeconds": {"Dev": 3.2}`) and relabel.
- `spotcheck` cuts 20 labeled intervals, spread across the session, from `table.wav` into `spotcheck/`. Play each clip and fill in `checklist.md`. **At least 19 of 20 must be right.** If fewer are, look at what went wrong (usually bleed: one member's device picking up someone louder nearby), fix the offsets or the recording, and relabel.
- Add the non-member spans you noted to `labels.json` (`"nonMemberSpans": [{"start": 300, "end": 330}]`). `label` keeps them when it relabels.

Then record the baseline:

```bash
minits-eval run eval/ --out eval/baseline.json
```
