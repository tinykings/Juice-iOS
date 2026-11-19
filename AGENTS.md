# Agent workflow

- Commit your changes when a task is done, with a clear message. Do not push.
- `Juice/Core` must stay plain Swift (Foundation only) so `swift test` runs on Linux. Run
  `swift test` after changing it.
- Anything that changes what's stored in CloudKit must follow `docs/sync-schema.md`, and
  both clients must change together: iOS (`Juice/Core/TaskLibrary.swift`,
  `Juice/Core/SyncCodec.swift`) and the website (tinykings/juice).
  `Tests/fixtures/juice-task-record.json` is the record both test suites decode.
- Title rules (@time, notes after the first period, date words), recurrence and the
  `.ics` reader are ports of the website's `src/utils/`; keep them in step.
- If an iOS Simulator is booted (`xcrun simctl list devices booted`), rebuild for it after
  changing the app:

  ```
  xcodebuild -project Juice.xcodeproj -scheme Juice -destination 'id=<booted UDID>' build
  ```
