# Juice for iPhone

A calm, warm task app: the iPhone companion to [Juice on the web](https://juice.tinyk.ing/),
synced through your private iCloud.

- **Tasks by day.** Overdue (and undated), Today, the next seven days, then later months.
  Today's completed tasks collapse under Today, with Undo after each completion.
- **Type it how you'd say it.** "Call mom tomorrow @5pm" is due tomorrow at 5 pm. Text after
  the first sentence's period is the note. Same rules as the website.
- **Repeating tasks**, daily to yearly. Completing one makes the next; a series on the 31st
  comes back to the 31st after shorter months.
- **Calendar.** Months from this one onward, with repeating tasks previewed and events from
  a subscribed `.ics` calendar. From the footer, or turn the phone sideways.
- **Siri and Shortcuts.** "Add a task in Juice", "What's due today in Juice", "Complete
  *task* in Juice", plus Open Add Task for the Action button.
- **iCloud sync** between devices and with Juice on the web, where you sign in with your
  Apple Account.

## Layout

| Path | What |
|---|---|
| `Juice/Core/` | Plain Swift: the task model, the synced library and its conflict rules, recurrence, date words / @time / notes, list grouping, the `.ics` reader. No UIKit/SwiftUI/CloudKit, so `swift test` runs it anywhere, including Linux. |
| `Juice/App/` | CloudKit sync (`CloudSync`, from [void]), the app's state (`TaskStore`), the subscribed calendar, Siri and Shortcuts (`Intents.swift`). |
| `Juice/Views/` | SwiftUI screens. |
| `Tests/` | `swift test` for `Juice/Core`, and a record fixture both clients decode. |
| `docs/sync-schema.md` | The CloudKit record format every client must follow. |

## Build

Open `Juice.xcodeproj` in Xcode (iOS 26+). The target uses team `7F4K5N55BN`, bundle ID
`com.tinykings.juice` and container `iCloud.com.tinykings.juice`. Debug builds use the
CloudKit Development environment, Release builds Production (`JUICE_CLOUDKIT_ENVIRONMENT`).

```
swift test        # Juice/Core, on any machine
```

## Setup (once)

1. **Apple Developer:** register the App ID `com.tinykings.juice` with iCloud (CloudKit) and
   the container `iCloud.com.tinykings.juice`. Xcode's automatic signing can do this.
2. **CloudKit schema:** run a Debug build on a device or simulator signed in to iCloud and
   add a task; that creates the `JuiceTask` record type in Development. In CloudKit
   Console, check its fields match `docs/sync-schema.md`, then **Deploy Schema Changes** to
   Production before TestFlight or the App Store.
3. **Website:** in CloudKit Console (Production) create a web API token with sign-in
   callback to `https://juice.tinyk.ing/` and allowed origin `juice.tinyk.ing`, for the
   website's move from Gist sync to CloudKit.

## To do

- App icon: `AppIcon.png` is the website's 512 px icon scaled up; replace it with a 1024 px
  original (and dark/tinted variants).
- The website (tinykings/juice) still syncs through a Gist; it moves to CloudKit next,
  following `docs/sync-schema.md`.
