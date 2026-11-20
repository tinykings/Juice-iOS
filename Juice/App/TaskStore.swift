import Combine
import Foundation
import UIKit

// The app's state: the synced tasks (CloudSync), the subscribed calendar, today's date,
// and the last change that can be undone. Shared with Siri and Shortcuts (Intents.swift),
// which run in this same process.
@MainActor
final class TaskStore: ObservableObject {
    static let shared = TaskStore()

    let sync = CloudSync()
    let calendarFeed = CalendarFeed()

    // Changes at midnight and when the time zone changes.
    @Published private(set) var today = CalendarDay.today()
    @Published private(set) var undo: Undo?
    @Published private(set) var refreshing = false
    // Set by Open Add Task (Intents.swift); the list opens the add form and clears it.
    @Published var addRequested = false

    func requestAdd() { addRequested = true }

    struct Undo: Identifiable, Equatable {
        enum Kind: Equatable { case completed, deleted }
        let id = UUID()
        let kind: Kind
        let taskID: String
        let title: String
    }

    private var forward: Set<AnyCancellable> = []
    private var undoTimer: Task<Void, Never>?

    private init() {
        sync.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &forward)
        calendarFeed.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &forward)
        NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
            .sink { [weak self] _ in Task { @MainActor in self?.updateToday() } }
            .store(in: &forward)
    }

    func updateToday() {
        let now = CalendarDay.today()
        if now != today { today = now }
    }

    // MARK: Reading

    var library: TaskLibrary { sync.library }

    func task(_ id: String) -> JuiceTask? { library.task(id) }

    var openTasks: [JuiceTask] { library.openTasks }

    func groups(matching query: String = "") -> [TaskSection] {
        let tasks = filter(openTasks, query)
        let events = query.isEmpty ? calendarFeed.events.filter { $0.date >= today } : []
        let groups = TaskGroups.build(open: tasks, events: events, today: today)
        // While searching, only groups with something in them.
        return query.isEmpty ? groups : groups.filter { !$0.items.isEmpty }
    }

    func completedToday(matching query: String = "") -> [JuiceTask] {
        filter(library.completedToday(), query)
    }

    // Open tasks due today or earlier, and undated ones: what Siri reads out.
    var dueNow: [JuiceTask] {
        openTasks.filter { ($0.dueDate ?? today) <= today }
            .sorted(by: TaskGroups.byDateAndTime)
    }

    private func filter(_ tasks: [JuiceTask], _ query: String) -> [JuiceTask] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return tasks }
        return tasks.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.notes.localizedCaseInsensitiveContains(q) }
    }

    // MARK: Changing

    @discardableResult
    func add(_ text: String, notes: String = "", dueDate: CalendarDay? = nil, recurrence: Recurrence? = nil,
             readDateWords: Bool = true) -> JuiceTask? {
        updateToday()
        // Siri and Shortcuts pass what was said; the add form has already read it.
        let draft = readDateWords
            ? TaskDraft(text: text, notes: notes, dueDate: dueDate, today: today)
            : TaskDraft(exactTitle: text, notes: notes, dueDate: dueDate)
        guard !draft.isEmpty else { return nil }
        var added: JuiceTask?
        sync.change { added = $0.add(draft, recurrence: draft.dueDate == nil ? nil : recurrence) }
        return added
    }

    func update(_ id: String, title: String, notes: String, dueDate: CalendarDay?, recurrence: Recurrence?) {
        sync.change { $0.update(id, title: title, notes: notes, dueDate: dueDate, recurrence: recurrence) }
    }

    func reschedule(_ id: String, to day: CalendarDay?) {
        sync.change { $0.reschedule(id, to: day) }
    }

    func moveOverdueToToday() {
        updateToday()
        sync.change { [today] in $0.moveOverdue(to: today) }
    }

    func complete(_ id: String) {
        guard let task = task(id), task.isOpen else { return }
        sync.change { $0.complete(id) }
        offerUndo(.completed, task)
    }

    func uncomplete(_ id: String) {
        sync.change { $0.uncomplete(id) }
    }

    func delete(_ id: String) {
        guard let task = task(id), !task.isDeleted else { return }
        sync.change { $0.delete(id) }
        offerUndo(.deleted, task)
    }

    func undoLast() {
        guard let undo else { return }
        switch undo.kind {
        case .completed: uncomplete(undo.taskID)
        case .deleted: sync.change { $0.restore(undo.taskID) }
        }
        dismissUndo()
    }

    func dismissUndo() {
        undoTimer?.cancel()
        undo = nil
    }

    private func offerUndo(_ kind: Undo.Kind, _ task: JuiceTask) {
        undo = Undo(kind: kind, taskID: task.id, title: task.parts.title)
        undoTimer?.cancel()
        undoTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.undo = nil
        }
    }

    // MARK: Syncing

    // On launch, on returning to the foreground, and from pull to refresh.
    func refresh() async {
        updateToday()
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        async let synced: Void = sync.syncNow()
        async let calendar: Void = calendarFeed.refreshIfStale()
        _ = await (synced, calendar)
    }

    // After Siri or a shortcut changes something: send it now, but don't keep Siri waiting
    // long. Whatever isn't sent stays pending and goes with the next sync.
    func pushSoon(timeout: Duration = .seconds(6)) async {
        final class Once {
            var done = false
        }
        let once = Once()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let finish: @MainActor () -> Void = {
                guard !once.done else { return }
                once.done = true
                continuation.resume()
            }
            // The sync carries on after the timeout; only the wait ends.
            Task { @MainActor in
                await self.sync.syncNow()
                finish()
            }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                finish()
            }
        }
    }
}
