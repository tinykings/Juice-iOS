import AppIntents
import Foundation

// Siri, Shortcuts, Spotlight and the Action button. The intents run in the app's process
// without opening it (except Open Add Task) and change tasks through TaskStore, then
// send the change to iCloud right away so it reaches the web and other devices.
//
// Siri needs the app's name in what's said: "Add a task in Juice", then the task when it
// asks. Date words in the task ("call mom tomorrow @5pm") set its date and time, as when
// typing it in the app.

// MARK: - Entities

enum RepeatOption: String, AppEnum {
    case daily, weekly, monthly, yearly

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Repeat"
    static let caseDisplayRepresentations: [RepeatOption: DisplayRepresentation] = [
        .daily: "Daily", .weekly: "Weekly", .monthly: "Monthly", .yearly: "Yearly",
    ]

    var recurrence: Recurrence { Recurrence(rawValue: rawValue)! }
}

struct TaskEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Task"
    static let defaultQuery = TaskQuery()

    let id: String
    let title: String
    let due: String

    @MainActor
    init(_ task: JuiceTask, today: CalendarDay = TaskStore.shared.today) {
        id = task.id
        title = task.parts.title
        due = TaskGroups.spokenDay(task.dueDate, today: today)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "Due \(due)")
    }
}

// Open tasks: the ones due now are suggested first.
struct TaskQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [TaskEntity] {
        identifiers.compactMap { TaskStore.shared.task($0) }.filter(\.isOpen).map { TaskEntity($0) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [TaskEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return TaskStore.shared.openTasks
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
            .sorted(by: TaskGroups.byDateAndTime)
            .prefix(20)
            .map { TaskEntity($0) }
    }

    @MainActor
    func suggestedEntities() async throws -> [TaskEntity] {
        let store = TaskStore.shared
        let soon = store.openTasks.filter { ($0.dueDate ?? store.today) <= store.today.adding(days: 7) }
        return soon.sorted(by: TaskGroups.byDateAndTime).prefix(20).map { TaskEntity($0) }
    }
}

// MARK: - Intents

struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Task"
    static let description = IntentDescription(
        "Adds a task to Juice. Words like “tomorrow” or “friday” in the task set its date, and “@5pm” its time; without either it's due today.")
    static let openAppWhenRun = false

    @Parameter(title: "Task", requestValueDialog: "What's the task?")
    var text: String

    @Parameter(title: "Due Date")
    var date: Date?

    @Parameter(title: "Repeat")
    var repeats: RepeatOption?

    @Parameter(title: "Notes")
    var notes: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) to Juice") {
            \.$date
            \.$repeats
            \.$notes
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<TaskEntity> & ProvidesDialog {
        let store = TaskStore.shared
        let due = date.map { CalendarDay($0) }
        guard let task = store.add(text, notes: notes ?? "", dueDate: due, recurrence: repeats?.recurrence) else {
            throw $text.needsValueError("What's the task?")
        }
        await store.pushSoon()
        let when = TaskGroups.spokenDay(task.dueDate, today: store.today)
        let time = task.timeMinutes.map { " at " + TaskTime.label(minutes: $0) } ?? ""
        return .result(value: TaskEntity(task), dialog: "Added “\(task.parts.title)” for \(when)\(time).")
    }
}

struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Task"
    static let description = IntentDescription("Marks a Juice task done. A repeating task gets its next date.")
    static let openAppWhenRun = false

    @Parameter(title: "Task", requestValueDialog: "Which task?")
    var task: TaskEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Complete \(\.$task)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = TaskStore.shared
        guard let current = store.task(task.id), current.isOpen else {
            return .result(dialog: "That task is already done.")
        }
        store.complete(task.id)
        await store.pushSoon()
        // A repeating task's next occurrence, if completing made one.
        if let series = store.task(task.id)?.seriesID,
           let next = store.task("\(series).\(current.occurrence + 1)"), next.isOpen {
            return .result(dialog: "Done. “\(current.parts.title)” is next due \(TaskGroups.spokenDay(next.dueDate, today: store.today)).")
        }
        return .result(dialog: "Done: “\(current.parts.title)”.")
    }
}

struct TodayTasksIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's Tasks"
    static let description = IntentDescription("Lists the Juice tasks due today, overdue, or without a date.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[TaskEntity]> & ProvidesDialog {
        let store = TaskStore.shared
        await store.pushSoon(timeout: .seconds(3)) // Pick up changes from other devices.
        let tasks = store.dueNow
        let entities = tasks.map { TaskEntity($0) }
        guard !tasks.isEmpty else {
            return .result(value: entities, dialog: "Nothing's due today.")
        }
        let names = tasks.prefix(5).map(\.parts.title)
        let list = ListFormatter.localizedString(byJoining: names)
        let more = tasks.count > 5 ? ", and \(tasks.count - 5) more" : ""
        let count = tasks.count == 1 ? "one task" : "\(tasks.count) tasks"
        return .result(value: entities, dialog: "You have \(count): \(list)\(more).")
    }
}

// Opens Juice to the add form: for the Action button, Control Center and Back Tap.
struct OpenAddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Add Task"
    static let description = IntentDescription("Opens Juice ready to type a new task.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        TaskStore.shared.requestAdd()
        return .result()
    }
}

// MARK: - Siri phrases

struct JuiceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add a task in \(.applicationName)",
                "Add a \(.applicationName) task",
                "New task in \(.applicationName)",
                "Add to \(.applicationName)",
                "Remind me in \(.applicationName)",
            ],
            shortTitle: "Add Task",
            systemImageName: "plus.circle")
        AppShortcut(
            intent: CompleteTaskIntent(),
            phrases: [
                "Complete \(\.$task) in \(.applicationName)",
                "Check off \(\.$task) in \(.applicationName)",
                "Mark a task done in \(.applicationName)",
            ],
            shortTitle: "Complete Task",
            systemImageName: "checkmark.circle")
        AppShortcut(
            intent: TodayTasksIntent(),
            phrases: [
                "What's due today in \(.applicationName)",
                "What's on my \(.applicationName) list",
                "Read my \(.applicationName) tasks",
            ],
            shortTitle: "Today's Tasks",
            systemImageName: "sun.max")
        AppShortcut(
            intent: OpenAddTaskIntent(),
            phrases: ["Open \(.applicationName) to add a task"],
            shortTitle: "Open Add Task",
            systemImageName: "square.and.pencil")
    }

    static let shortcutTileColor: ShortcutTileColor = .orange
}
