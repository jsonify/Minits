# Competitive research: features worth bringing to Minits

November 2026. This surveys apps close to Minits and picks the ideas that would make it better. It doesn't copy their feature lists. Every idea here runs **entirely on the device** (no accounts, no servers) and serves **board meetings and ad-hoc meetings equally**.

## What Minits already does well

Most of the field can't match a few things Minits already does, so the ideas below build on them instead of competing with them:

- **Voiceprints that persist by name.** Most rivals label speakers "Speaker 1, Speaker 2" for each meeting. Minits knows *who* each person is across meetings. Only a few on-device apps (talat, for one) say they learn voices over time.
- **In-person, one phone, no bot.** Granola and Otter are built around video calls. Plaud needs a $159+ hardware pin to get a physical "highlight" press. Minits already has **Mark motion / Mark moment**, plus a Live Activity that works without unlocking.
- **Board-specific output.** It produces motions with mover, seconder and vote, and a printable PDF.
- **Review as a first-class step.** Flagged lines, split lines, and Guest naming.

## Apps surveyed

| App | Kind | Ideas worth taking |
|---|---|---|
| **Granola** | AI notepad for calls (Mac, Windows, iPhone) | Typed notes merged with the transcript. Chat across months of notes **with citations**. Pre-meeting briefs from past notes. "Recipes" (reusable prompts) |
| **Plaud NotePin S / Note Pro** | Hardware recorder and app | Press to Highlight: marked moments are weighted first in the summary. Ask Plaud. Thousands of templates |
| **Otter, Fireflies, tl;dv, Claap, Avoma** | Cloud meeting bots | Search across the whole archive. Soundbites (shareable clips). Talk-time and monologue analytics. Custom vocabulary |
| **MinuteSmith** (HOA, condo, nonprofit) | AI minutes | Extracts motions, decisions and action items. **Draft approval workflow.** Searchable meeting history |
| **BoardBreeze** | AI board minutes | Roll-call votes, public comment, audit trail |
| **CaseMark** | Nonprofit minutes workflow | Automatic **quorum checks** against state rules |
| **iDeals, BoardEffect / Diligent, Aprio, TidyHQ** | Board portals | **Agenda becomes the minutes template.** Approved minutes go into the next meeting book. Action items roll forward until they're done |
| **Municipal clerk AI tools** | Government minutes | The agenda plus recording produce minutes in the required format. The clerk certifies the result |
| **talat, Synopsule, Vocatim, HuddleNotes, Meeting Assist Local** | On-device transcribers | Fully local pipelines, some with voices learned over time (the space Minits competes in) |
| **Apple Notes (iOS 26)** | Built-in | Call recording with a transcript and an Apple Intelligence summary. Free, but no speakers and no structure |

The main takeaway: **cloud tools treat each meeting as a separate file, and board portals treat meetings as a governed series.** Minits can do both, on the device, and only Minits knows everyone's voice.

## Recommendations, ranked

Each idea has a GitHub issue (labelled `enhancement`), linked from its heading.

Each idea gives the source of inspiration, what Minits would do, why it fits Minits in particular, and where it would go in the code.

### 1. Voice roll-call votes: the board's vote, counted by voice ★ ([#45](https://github.com/jsonify/Minits/issues/45))

**Inspired by:** BoardBreeze's roll-call votes. The California clerk rule that "at a member's request, the clerk shall enter the ayes and noes."

**What it does:** When the secretary taps **Mark motion**, the LCD offers **Call the vote**. Each member then says "aye", "no" or "abstain", and Minits uses the voiceprints it already has to record **who voted what**, not only that the motion passed. The motion card shows `AYE 4 · NO 0 · ABSTAIN 1 (R. James)`. Any vote it isn't sure of goes to Review like any other flagged line.

**Why only Minits can do this:** Cloud tools hear "aye" from Speaker 3. Minits hears it from *Maria Lopez, Treasurer*. Done well, this replaces the most error-prone thing a secretary writes down.

**Where:** Diarization is already split by voice (`Voice/VoiceEngine.swift`). Short words like "aye" are hard (see issue #7, crosstalk), so attribute votes from the time window right after the mark. Build it as a structured `Motion` model (below) rather than prose, and score it with `minits-eval`.

### 2. Motions and action items as data, not just prose ([#44](https://github.com/jsonify/Minits/issues/44))

**Inspired by:** MinuteSmith's extraction, Diligent's carry-over action items, and Taskade's mover/seconder/outcome log.

**What it does:** Store `Motion` (text, mover, seconder, vote tally, outcome, time) and `ActionItem` (owner as a `Member`, task, due date, done, source line) in SwiftData, filled from the draft and correctable by hand. The minutes are then *rendered* from them. Everything else on this list builds on this.

**Why it's thoughtful:** Today a fix to a vote in the draft text is lost on **Redraft**. With data, the correction is kept and every later draft includes it.

**Where:** `Models/Models.swift`, plus a structured-output pass in `Minutes/MinutesWriter.swift` (FoundationModels `@Generable`), keeping the outline fallback for devices without Apple Intelligence.

### 3. The meeting series: open items, prior minutes and the brief ([#46](https://github.com/jsonify/Minits/issues/46))

**Inspired by:** Granola's pre-meeting briefs, the board portals' "roll forward to next meeting", and Diligent sending finished minutes into the next meeting for approval.

**What it does:** Meetings of the same group form a **series** (the same title stem or the same members). At the next roll call:
- An **Open from last time** tray lists unfinished action items, each with its owner's avatar. Tick them off as people report back.
- For a board: **Approve last meeting's minutes** is the first business item. When it passes (a motion, #1), the earlier minutes change from `DRAFT` to `APPROVED <date>`, and the PDF shows which one it is.
- A short **brief** LCD shows the last meeting's decisions and anything left unresolved.

**Why it's thoughtful:** Minutes are a legal record for HOAs and nonprofits, and "draft vs approved" is the distinction secretaries most often get wrong. For ad-hoc meetings (a family, a club) it answers "what did we say we'd do?" without anyone digging.

**Where:** A new `MeetingSeries` (or a `seriesID` on `Meeting`), `UI/RollCallView.swift`, and `Export/MinutesPDF.swift` (approval state in the header).

### 4. Agenda-first meetings ([#47](https://github.com/jsonify/Minits/issues/47))

**Inspired by:** iDeals ("your agenda becomes your minutes template") and the municipal clerk tools (agenda plus recording produce formatted minutes).

**What it does:** Optionally paste or type the agenda at roll call (or bring the open items from #3 forward). While recording, a **Next item** key steps through the agenda, and the LCD shows `ITEM 3 OF 7 · TREASURER'S REPORT`. The draft is then split by agenda item using real times, instead of guessing "Old Business vs New Business" from the transcript.

**Why it's thoughtful:** Splitting the transcript by item is what the on-device model does worst. One tap per item fixes it for good, and it fits the SK-1 hardware feel (a key that advances a counter).

**Where:** `UI/RecordingView.swift`, `LiveActivity/` (a Next item key on the lock screen), and the chunking in `MinutesWriter.chunk`, which can split at agenda boundaries.

### 5. Every sentence of the minutes traced back to the tape ([#48](https://github.com/jsonify/Minits/issues/48))

**Inspired by:** Granola's chat citations. Clerks still "certify the accuracy of the final minutes."

**What it does:** In the draft, tap any sentence (*"Moved by M. Lopez, seconded by D. Chen"*) and the cassette deck plays the lines it came from. Sentences with no clear source get a dim amber lamp, the same idea as today's `[CHECK]`, but found automatically.

**Why it's thoughtful:** An on-device model is small and can make things up. Letting the person who signs the minutes check each claim in a couple of seconds is the most valuable trust feature an AI minutes app can have. It also uses the existing deck and per-word times.

**Where:** Ask the model to cite `[TIME]` markers (the notes prompt already includes them), map them to `TranscriptLine`s, and play through `Audio/MeetingPlayer.swift`.

### 6. Off-the-record: executive session and redaction ([#49](https://github.com/jsonify/Minits/issues/49))

**Inspired by:** board practice (closed or executive sessions on personnel, legal or contracts) and open-meeting rules. No rival handles this well.

**What it does:**
- **Executive session** key while recording. That stretch is left out of the transcript and the draft, and recorded in the minutes as *"The board went into executive session at 8:14 pm and returned at 8:40 pm."* The audio for it is kept apart, or never kept at all, which is the user's choice.
- **Redact** in Transcript: select lines and remove both the text *and the audio* (silenced in the WAV), for the moment someone says "don't put this in."

**Why it's thoughtful:** It's the privacy promise taken past "nothing leaves the device" to "*you* decide what's kept." It's also legally meaningful for boards.

**Where:** `Audio/AudioRecorder.swift` (pause-and-mark or a separate file), and a redaction pass on the WAV and its lines.

### 7. Ask your meetings, on the device ([#50](https://github.com/jsonify/Minits/issues/50))

**Inspired by:** Granola chat (months of notes, with citations), Ask Plaud, and Fireflies' archive search.

**What it does:** A search field on Home: *"When did we last raise the dues?"* or *"What did Grandpa say about the trip?"* Minits searches every transcript on the device, and the on-device model answers from the matching lines. Each answer cites meetings and times you can play. Without Apple Intelligence it still works as plain search with the lines shown.

**Why it's thoughtful:** The cloud tools sell this as their main feature. Minits can offer the same thing with nothing uploaded, and it's searchable *by who said it* ("everything the Treasurer said about the roof").

**Where:** Natural Language `NLEmbedding` or keyword index over `TranscriptLine`, and a `LanguageModelSession` for the answer. A new Home tray.

### 8. Quorum lamp ([#51](https://github.com/jsonify/Minits/issues/51))

**Inspired by:** CaseMark's automatic quorum checks and the board portals' "notify if quorum is not met."

**What it does:** Set the board size and quorum rule once (a majority, or a fixed number). Roll call shows `QUORUM ✓ 5 OF 9` or a red `NO QUORUM`. During the meeting, **Mark arrival / departure** updates it, and if a motion is marked while there's no quorum, an amber lamp warns. The minutes record "A quorum was present."

**Why it's thoughtful:** It's small, but it's exactly the kind of mistake that invalidates a vote, and Minits already knows who's present.

**Where:** `UI/RollCallView.swift`, `UI/RecordingView.swift`, and attendance in the PDF.

### 9. A note on the mark ([#52](https://github.com/jsonify/Minits/issues/52))

**Inspired by:** Granola (typed notes plus transcript) and Plaud (highlights weighted first in the summary).

**What it does:** After tapping Mark, an optional one-line note: *"dues increase"* or *"Sam agrees to book the venue."* The note goes into the draft prompt as the secretary's intent, labels the chip (`MOTION 2 · DUES · 12:04`), and becomes the first guess for that motion's text.

**Why it's thoughtful:** It's the one part of Granola's model that suits in-person meetings: a few words from a person steer the AI better than any prompt. Minits already passes marks as hints (`Prompts.markHint`), so this adds meaning to them.

**Where:** `Meeting.motionMarks` becomes an array of `Mark { time, note }`, plus `RecordingView` and `MinutesWriter.Prompts`.

### 10. Names spelled right: the group's vocabulary ([#53](https://github.com/jsonify/Minits/issues/53))

**Inspired by:** custom vocabulary in Otter and Fireflies.

**What it does:** Member names, roles, and a short list of words the group uses (street names, "Larkspur HOA", "CAM fees") are used to correct the transcript, by fuzzy-matching misheard words after transcription. Check whether FluidAudio/Parakeet supports biasing words up front. Words the user fixes in Review are added to the list.

**Where:** A post-pass in `VoiceEngine`, and a list on the People screen.

### 11. Apple-native handoffs that stay on the device ([#54](https://github.com/jsonify/Minits/issues/54))

- **Action items to Reminders** (EventKit), each with its owner in the note and a due date: one key on the minutes screen.
- **Calendar-aware titles**: if a calendar event is happening now, offer its title and attendees at roll call (EventKit reads locally).
- **App Intents and a Control Center control**: "Start board meeting" from Siri, Shortcuts, the Action Button, or Control Center.
- **Apple Watch** as a remote for Mark, Pause and Next item, so the secretary isn't touching the phone in the middle of the table.

### 12. Fair-floor view (optional, for chairs) ([#55](https://github.com/jsonify/Minits/issues/55))

**Inspired by:** talk-time analytics in Fireflies, tl;dv, Claap and Avoma. Those exist to coach salespeople. Minits can use the same data with a kinder purpose.

**What it does:** After the meeting, a quiet LCD shows how long each person spoke, so a chair can see "three members never got the floor." It's off by default, never ranked, and never in the minutes.

**Where:** Computed from `TranscriptLine` durations, shown in a Meeting tab.

### 13. Next meeting: the next agenda, on the calendar before everyone leaves ([#56](https://github.com/jsonify/Minits/issues/56))

**Inspired by:** board portals rolling open items forward into the next meeting book, and Granola's briefs. Suggested in review of this research.

**What it does:** When a board meeting is processed, a **Next meeting** step drafts the next agenda: the standard order (Call to Order, Approval of these minutes, Reports, Old Business, New Business, Adjournment), with Old Business filled from unfinished action items and tabled motions, and New Business from anything someone said should go on the next agenda. The date and time come from the meeting if someone said one, or else the same weekday and time next month. Edit it in an LCD tray, then put it on the calendar:

- **Through the phone's own calendar (EventKit).** Minits creates the event, with the agenda in the notes, in whichever calendar you pick. **Zoho Calendar** works through CalDAV: add the Zoho account once in Settings › Calendar › Accounts › Add Account › Other › CalDAV (server `calendar.zoho.com`, or your regional one), and iOS or macOS syncs the event to Zoho. Google, Outlook and iCloud work the same way. EventKit can't add invitees itself, so Minits opens the system's event editor already filled in and you add the board.
- **Share invite.** An `.ics` file with the agenda, through the share sheet, for anyone without a calendar account on the device.

The agenda then loads at the next roll call (#3, #4).

**Why it's thoughtful:** The next meeting is scheduled while everyone's still in the room, and nothing is forgotten between meetings. Going through the device's calendar keeps Minits off the network, with no Zoho login to store, and works for every calendar provider. Connecting to Zoho's API directly would invite people automatically, but it needs a Zoho sign-in and a registered app, and it sends the agenda to Zoho's servers, so it's left out.

**Where:** A new step after the minutes in `UI/MinutesView.swift`, EventKit and EventKitUI for the event, and an `.ics` writer next to `Export/MinutesPDF.swift`. Depends on #2.

## What not to copy

- **Cloud chat, sync and a public API** (Granola, Fireflies): these would break the core promise. #7 gives the benefit without them.
- **Joining video calls with a bot**: Minits is for in-person meetings. Recording Mac system audio for hybrid boards might be worth a separate look later.
- **Thousands of templates** (Plaud): two well-made kinds (board and ad-hoc), plus agenda-driven structure (#4), suit this audience better than a gallery.
- **Leaderboards of who spoke most**: #12 stays private and gentle on purpose.

## Suggested order

1. **#2 Motions and action items as data.** It's the foundation for #1, #3, #5, #11 and #13.
2. **#9 Note on the mark** and **#4 Agenda-first**: small changes that make every draft better.
3. **#3 The meeting series** (open items, approval of prior minutes), then **#13 Next meeting** on top of it.
4. **#1 Voice roll-call votes**: the standout feature, built once issues #7 (crosstalk) and #9 (the attribution epic) make short words reliable.
5. **#5 Traced sentences**, **#6 Off-the-record**, **#7 Ask your meetings**.
6. The rest as they fit.

## Sources

- [Granola reviews and changelog summaries (SkillScouter)](https://skillscouter.com/granola-review/), [aitoolsatlas: Granola](https://aitoolsatlas.ai/tools/granola), [yespress: Granola](https://yespress.io/granola), [toolfinder: in-person AI note-takers](https://toolfinder.com/best/ai-note-takers-for-in-person-meetings)
- [Plaud NotePin vs NotePin S (Press to Highlight)](https://www.plaud.ai/blogs/articles/plaud-notepin-vs-plaud-notepin-s), [Plaud NotePin S guide](https://tech-now.io/?p=73828), [Plaud app on the App Store](https://apps.apple.com/gb/app/id6450364080)
- [MinuteSmith on Capterra](https://www.capterra.ca/software/1102483/MinuteSmith), [BoardBreeze on G2](https://www.g2.com/products/boardbreeze/discuss), [CaseMark nonprofit minutes](https://casemark.com/workflows/minutes-of-non-profit-board-meeting), [Taskade board minutes](https://www.taskade.com/convert/audio-to-notes/board-meeting-audio-to-minutes), [Fireflies: AI meeting minutes](https://fireflies.ai/blog/ai-meeting-minutes/)
- [iDeals agendas](https://idealsboard.com/agendas), [iDeals product overview](https://idealsboard.com/product-overview/), [BoardEffect](https://boardeffect.com/?p=11685), [Aprio board meeting software](https://aprioboardportal.com/board-meeting-software/), [TidyHQ meetings](https://tidyhq.com/products/meetings), [HOA board meeting software guide](https://boardstack-web.pages.dev/resources/guides/hoa-board-meeting-management-software/), [Capterra: board management features](https://www.capterra.com/resources/board-management-software-features/)
- [GovTech: AI and meeting minutes](https://www.govtech.com/artificial-intelligence/ai-takes-the-drudgery-out-of-compiling-meeting-minutes), [Brass Transcripts: government meetings](https://brasstranscripts.com/blog/government-meeting-documentation-ai-transcription-minutes), [Smart Cities Dive: AI for municipal clerks](https://www.smartcitiesdive.com/news/ai-municipal-clerks-speed-up-public-records-reporting/820216/)
- On-device apps: [Synopsule](https://hunted.space/product/synopsule), [Vocatim](https://apps.apple.com/app/id6761047706), [Meeting Assist Local](https://apps.apple.com/app/id6759475140), [AI Meeting Notes – Transcribe](https://apps.apple.com/us/app/-/id6759388036), [HuddleNotes](https://mwm.ai/apps/huddlenotes-meeting-notes/6778677679), [Minuted](https://mwm.ai/apps/minuted-ai-meeting-notes/6781033691)
- Talk-time analytics: [Fireflies conversation intelligence](https://guide.fireflies.ai/articles/2608597716-understand-fireflies-analytics-and-conversation-intelligence), [tl;dv speaker insights](https://intercom.help/tldv/en/articles/9041193-speaker-insights), [Claap speaker insights](https://help.claap.io/en/articles/7252571-speaker-insights), [Avoma speaker percentages](https://help.avoma.com/speaker-percentages-and-monologues)
- Zoho Calendar: [CalDAV sync setup](https://www.zoho.com/calendar/help/setup-caldav-sync.html), [Sync Zoho Calendar on iPhone](https://www.zoho.com/calendar/how-to/sync-calendar-on-iphone.html), [Deluge: create event (API)](https://www.zoho.com/deluge/help/calendar/create-event.html)
- Apple: [Gadget Hacks: iOS 26 Notes](https://ios.gadgethacks.com/news/why-ios-26-turns-apple-notes-into-the-productivity-powerhouse-you-never-knew-you-needed/), [MacRumors: Notes and Reminders in iOS 26](https://www.macrumors.com/2025/06/09/four-features-coming-to-apple-reminders-and-notes/)

Most competitor details come from vendor pages and review sites rather than hands-on testing. ProductHunt, GetApp and Peerlist pages couldn't be reached from the research environment.
