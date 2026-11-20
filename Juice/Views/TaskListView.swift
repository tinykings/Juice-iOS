import SwiftUI

// Overdue, Today (with today's completed tasks), the next seven days, then later months.
struct TaskListView: View {
    @EnvironmentObject private var store: TaskStore
    let query: String
    let onEdit: (String) -> Void
    let onAdd: (CalendarDay?) -> Void

    var body: some View {
        let groups = store.groups(matching: query)
        let completed = store.completedToday(matching: query)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(groups) { group in
                    GroupSection(group: group, onEdit: onEdit, onAdd: onAdd)
                    if group.isToday && !completed.isEmpty {
                        CompletedSection(tasks: completed)
                    }
                }
                if !query.isEmpty && groups.isEmpty && completed.isEmpty {
                    Text("No tasks match “\(query)”.")
                        .font(.taskNote)
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await store.refresh() }
    }
}

struct GroupSection: View {
    @EnvironmentObject private var store: TaskStore
    let group: TaskSection
    let onEdit: (String) -> Void
    let onAdd: (CalendarDay?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ForEach(group.items) { item in
                switch item {
                case .task(let task):
                    TaskRow(task: task, dateLabel: TaskGroups.dateLabel(task, in: group, today: store.today),
                            overdue: group.isOverdue, onEdit: { onEdit(task.id) })
                case .event(let event):
                    EventRow(event: event)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(group.label)
                .font(group.isToday ? .system(size: 15, weight: .bold) : .groupHeader)
                .foregroundStyle(group.isOverdue ? Palette.red : group.isToday ? Palette.foreground : Palette.muted)
            if let detail = group.detail {
                Text("· \(detail)")
                    .font(.meta)
                    .foregroundStyle(Palette.muted)
            }
            if group.day != nil {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.muted.opacity(0.7))
            }
            Spacer()
            if group.isOverdue && group.items.count >= 2 {
                Button("Move all to today") {
                    withAnimation(.snappy) { store.moveOverdueToToday() }
                }
                .font(.meta.weight(.semibold))
                .foregroundStyle(Palette.accent)
            }
        }
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            // Tapping a day's header adds a task on that day.
            if let day = group.day { onAdd(day) }
        }
        .accessibilityAddTraits(group.day == nil ? [] : .isButton)
        .accessibilityHint(group.day == nil ? "" : "Adds a task on this day")
    }
}

struct TaskRow: View {
    @EnvironmentObject private var store: TaskStore
    let task: JuiceTask
    var dateLabel: String?
    var overdue = false
    var compact = false
    let onEdit: () -> Void

    @State private var checked = false

    var body: some View {
        let parts = task.parts
        HStack(alignment: .top, spacing: 12) {
            CheckCircle(checked: checked, overdue: overdue) {
                guard !checked else { return }
                withAnimation(.easeOut(duration: 0.2)) { checked = true }
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    withAnimation(.snappy) { store.complete(task.id) }
                    checked = false
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(parts.title)
                    .font(.taskTitle)
                    .foregroundStyle(Palette.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if !parts.note.isEmpty && !compact {
                    Text(parts.note)
                        .font(.taskNote)
                        .foregroundStyle(Palette.muted)
                        .lineLimit(3)
                }
                meta
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RescheduleMenu(task: task, onPick: onEdit)
        }
        .padding(11)
        .background(Palette.taskSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.border, lineWidth: 1))
        .opacity(checked ? 0.5 : 1)
        .offset(x: checked ? -12 : 0)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture(perform: onEdit)
        .contextMenu {
            Button("Edit", systemImage: "pencil", action: onEdit)
            Button("Tomorrow", systemImage: "arrow.right") { store.reschedule(task.id, to: store.today.adding(days: 1)) }
            Button("Delete", systemImage: "trash", role: .destructive) { store.delete(task.id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Complete") { store.complete(task.id) }
    }

    @ViewBuilder
    private var meta: some View {
        let time = task.timeMinutes.map(TaskTime.label(minutes:))
        if time != nil || task.isRecurring || dateLabel != nil {
            HStack(spacing: 10) {
                if let dateLabel {
                    Label(dateLabel, systemImage: "calendar")
                        .foregroundStyle(overdue ? Palette.red : Palette.muted)
                }
                if let time {
                    Label(time, systemImage: "clock")
                        .foregroundStyle(Palette.event)
                }
                if let recurrence = task.recurrence, task.isRecurring {
                    Label(recurrence.label, systemImage: "repeat")
                }
            }
            .font(.meta)
            .foregroundStyle(Palette.muted)
            .labelStyle(MetaLabelStyle())
            .padding(.top, 2)
        }
    }
}

struct MetaLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 11, weight: .semibold))
            configuration.title
        }
    }
}

struct CheckCircle: View {
    let checked: Bool
    var overdue = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(checked ? .clear : Palette.checkbox, lineWidth: 1.5)
                    .background(Circle().fill(checked ? (overdue ? Palette.red : Palette.accent) : .clear))
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Palette.background)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 24, height: 24)
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-10)
        .sensoryFeedback(.success, trigger: checked) { _, new in new }
        .accessibilityLabel(checked ? "Completed" : "Complete")
    }
}

// Today, Tomorrow, the next four weekdays, Next week, or pick a date.
struct RescheduleMenu: View {
    @EnvironmentObject private var store: TaskStore
    let task: JuiceTask
    let onPick: () -> Void

    var body: some View {
        let today = store.today
        Menu {
            Button("Today") { move(today) }
            Button("Tomorrow") { move(today.adding(days: 1)) }
            ForEach(2..<6, id: \.self) { offset in
                let day = today.adding(days: offset)
                Button(TaskGroups.format(day, "EEEE")) { move(day) }
            }
            Button("Next week") {
                let until = (8 - today.weekday) % 7
                move(today.adding(days: until == 0 ? 7 : until))
            }
            Divider()
            Button("Pick a date…", action: onPick)
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.muted)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Reschedule")
    }

    private func move(_ day: CalendarDay) {
        withAnimation(.snappy) { store.reschedule(task.id, to: day) }
    }
}

struct EventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Palette.event)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.foreground)
                Text(event.timeLabel() ?? "All day")
                    .font(.meta)
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Calendar event: \(event.title), \(event.timeLabel() ?? "all day")")
    }
}

// Today's completed tasks, collapsed under Today. Tapping the check reopens one.
struct CompletedSection: View {
    @EnvironmentObject private var store: TaskStore
    let tasks: [JuiceTask]
    @AppStorage("completedExpanded") private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Completed · \(tasks.count)")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .font(.groupHeader)
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 2)
            }
            .buttonStyle(.plain)
            if expanded {
                ForEach(tasks) { task in
                    HStack(spacing: 12) {
                        CheckCircle(checked: true) {
                            withAnimation(.snappy) { store.uncomplete(task.id) }
                        }
                        .accessibilityLabel("Mark not done")
                        Text(task.parts.title)
                            .font(.taskTitle)
                            .strikethrough(color: Palette.muted)
                            .foregroundStyle(Palette.muted)
                        Spacer()
                    }
                    .padding(11)
                    .background(Palette.inset.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }
}
