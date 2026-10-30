# Minits

## Pull requests: always say how to test

Every PR description has a **How to test** section written for the person merging it. Its job is to make sure nothing gets merged untested because they didn't know it needed checking.

- **Manual checks first.** List every check that automated tests don't cover, as numbered steps: where to start, what to tap or run, and what you should see. Name the platform (iPhone, Mac, or both) and any setup (a saved member, a recorded meeting, models downloaded).
- **UI changes.** Any change under `Minits/UI/`, or any change that alters what a screen shows, needs a functional walkthrough of each affected screen. Cover the happy path, empty and error states, and anything that differs between iOS and macOS (layout, permissions, background recording). The unit tests here don't exercise the UI, so a UI change is never covered by "tests pass".
- **Knock-on effects.** Name screens or flows the change could affect indirectly (for example, a `VoiceEngine` change shows up in Review flags and in who each line is attributed to), and say how to spot a regression.
- **No manual checks needed?** Say so in one line and why (for example, "eval-only code; no app or UI change").
- **Automated tests.** Then list what was run and the result (`xcodebuild test -scheme MinitsEvalTests`, `MinitsTests`, app builds for iOS and macOS). Mark anything not run as not run.

## README: keep it current

Every change that adds or changes a feature updates `README.md` in the same PR: what it does, how to use it (commands, flags, screens), and the project layout if files moved or were added. A feature isn't done until the README describes it. If a PR needs no README change, say why in its description.
