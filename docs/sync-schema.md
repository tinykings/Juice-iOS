# Juice CloudKit sync schema (v1)

Status: in use by iOS (`Juice/Core/TaskLibrary.swift`, `Juice/Core/SyncCodec.swift`,
`Juice/App/CloudSync.swift`). The website (tinykings/juice) must read and write exactly
this format when it moves to CloudKit. The design follows [void]'s sync
(tinykings/Void-iOS `docs/sync-schema.md`): one record per task, conditional writes,
and pending intentions kept per field group.

Container: **`iCloud.com.tinykings.juice`**. The record type below is created in
Development by running a Debug build, then deployed to Production in CloudKit Console.
Production never creates record types.

Console field types: every field is String except `recurrenceDay`, `occurrence` and
`schemaVersion`, which are Int(64). No indexes are required.

## Zone

Private database, custom zone **`JuiceSync`**, so clients fetch incremental changes
with a sync token (`records/changes` on the web, `recordZoneChanges` on iOS). Only iOS
creates the zone, when it's missing; if it disappears (the user deleted iCloud data),
iOS recreates it and pushes its pending intentions again. The website never creates it:
with no zone it pushes nothing, keeps its pending intentions, and says to open Juice on
iPhone first.

Times are ISO 8601 UTC strings with milliseconds (`2026-11-19T22:04:05.123Z`). Due dates
are local calendar dates, `YYYY-MM-DD`. Do not copy Swift `JSONEncoder`'s default `Date`
encoding into these fields.

Every record has `schemaVersion` (INT64, currently `1`). A client ignores records with a
higher version rather than misreading or overwriting them.

## `JuiceTask`: one per task

| Field | Type | |
|---|---|---|
| recordName | | `task.<id>`. `<id>` is 1–200 of `A-Z a-z 0-9 - .`: a UUID for a new task, `<seriesID>.<occurrence>` for a recurring task's later occurrences |
| `title` | STRING | 1–1000 characters, trimmed. May hold an `@time` (`@9am`, `@2:30pm`) and, after the first sentence-ending period, a note: the clients' existing title rules |
| `notes` | STRING | Free text, at most 10 000 characters, or empty |
| `dueDate` | STRING | `YYYY-MM-DD`, or empty for an undated task |
| `recurrence` | STRING | `daily`, `weekly`, `monthly`, `yearly`, or empty. Ignored (read as empty) when `dueDate` is empty |
| `recurrenceDay` | INT64 | For a monthly or yearly series whose day some months lack (29–31): the day it returns to after a shorter month. `0` otherwise |
| `seriesID` | STRING | The id of the task that started this recurring series, or empty |
| `occurrence` | INT64 | Which occurrence of its series this is, from `0` |
| `createdAt` | STRING | ISO time the task was created |
| `completedAt` | STRING | ISO time it was completed, or empty while open |
| `deletedAt` | STRING | ISO time it was deleted, or empty. Non-empty makes the record a tombstone |
| `schemaVersion` | INT64 | `1` |

A task is **open** while `completedAt` and `deletedAt` are empty, **done** when
`completedAt` is set, and **deleted** when `deletedAt` is set.

### Fields and intentions

A local change marks the field groups it changed as pending, durably (it survives being
offline and relaunches). Groups:

- **content**: `title`, `notes`
- **schedule**: `dueDate`, `recurrence`, `recurrenceDay`, `seriesID`, `occurrence`
- **done**: `completedAt`
- **removed**: `deletedAt`

`createdAt` is written once, when the task is created; a remote copy's value is taken.

### Rules shared by every client

- **Adding** writes every field: a new UUID, `createdAt = now`, the rest empty or `0`
  unless given.
- **Editing** the title or notes writes **content**. Changing the date or repeat writes
  **schedule**; a task moved to another day drops `recurrenceDay` (its series starts over
  from the new day).
- **Completing** writes `completedAt = now` (**done**). Completing an open recurring task
  also creates its next occurrence:
  - id `<seriesID>.<occurrence + 1>`, where `seriesID` is the task's own `seriesID`, or
    its id when that's empty. The completed task gets the same `seriesID` (**schedule**)
    if it had none.
  - The same `title`, `notes`, `recurrence` and `seriesID`, `occurrence + 1`,
    `createdAt = now`, open.
  - `dueDate` is the next date in the series after the completed one, skipping dates on
    or before today, so it isn't overdue as soon as it's made. Monthly and yearly series
    aim for `recurrenceDay` when it's set, or the completed date's day, clamped to the
    month's length (Jan 31 → Feb 28 → Mar 31); the new task keeps `recurrenceDay` only
    when that day is above 28.
  - Because the id depends only on the series, two devices that complete the same
    occurrence create the same record, not two.
- **Un-completing** clears `completedAt` (**done**) and deletes the occurrence that
  completing created, if it's still open and has the same title.
- **Deleting** writes `deletedAt = now` (**removed**). Writing a new occurrence over a
  tombstone (completing again after un-completing) clears it.

### What each list shows

- **Tasks:** open tasks. Undated tasks and tasks due before today are grouped as
  Overdue; then Today, the next seven days, then one group per later month. Within a day,
  tasks with an `@time` come first, earliest first, then the rest alphabetically.
- **Completed:** tasks completed since local midnight today, most recent first.
- Tasks completed before today are no longer shown.

### Clean-up

Records are never deleted while they could still matter to an offline client. iOS
deletes (a real CloudKit delete) records whose `deletedAt` or `completedAt` is more than
30 days old. A client that sees a record deleted forgets it, unless it has a pending
intention for it, which then creates it again.

## Writing and conflicts

- Writes are conditional: `update` with the last known `recordChangeTag`, or `create`
  when none is known (fails with `EXISTS` if another client created it). Never
  `forceUpdate` / `.allKeys` overwrite.
- On `CONFLICT` / `EXISTS`, fetch changes, then reapply: the remote record's fields are
  taken, except the field groups with pending local intentions, which keep their local
  values and are written again over the newer revision (the last accepted intention
  wins, per field group; offline edits can win when they reconnect). So an edit on one
  device and a delete on another leave the task deleted, with the edit applied.
- Turning sync on with tasks made before it was on is an **import**: it creates records
  only where none exist and never overwrites a remote record or tombstone.
- Order competing devices by accepted writes, not by their clocks.

## Accounts

Data is per Apple Account (`userRecordName`) and per container/environment. Changing
account hides the previous account's tasks and keeps its pending intentions apart, never
pushing them to the new account.

## Not synced

The subscribed calendar (`.ics` link) and its events, the theme, and the app badge
setting are per device.
