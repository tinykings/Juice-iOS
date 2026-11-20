import SwiftUI

// Months from this one onward, more loading as you scroll. Every open task, recurring
// preview and calendar event shows on its day; tapping a day lists them.
struct CalendarView: View {
    @EnvironmentObject private var store: TaskStore
    let query: String
    let onEdit: (String) -> Void
    let onAdd: (CalendarDay?) -> Void

    @State private var monthCount = 4
    @State private var selected: CalendarDay?

    struct Chip: Identifiable {
        enum Kind { case task, overdue, preview, event }
        let id: String
        let title: String
        let kind: Kind
        let sort: Int
    }

    var body: some View {
        let today = store.today
        let months = (0..<monthCount).map { today.firstOfMonth.adding(months: $0) }
        let chips = chipsByDay(months: months, today: today)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22, pinnedViews: [.sectionHeaders]) {
                ForEach(months) { month in
                    Section {
                        MonthGrid(month: month, today: today, chips: chips, onSelect: { selected = $0 })
                            .onAppear {
                                if month == months.last { monthCount += 3 }
                            }
                    } header: {
                        Text(TaskGroups.format(month, "MMMM yyyy"))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Palette.foreground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .background(Palette.background)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 24)
        }
        .refreshable { await store.refresh() }
        .sheet(item: $selected) { day in
            DaySheet(day: day, onEdit: { id in
                selected = nil
                onEdit(id)
            }, onAdd: { day in
                selected = nil
                onAdd(day)
            })
            .environmentObject(store)
            .presentationDetents([.medium, .large])
        }
    }

    private func chipsByDay(months: [CalendarDay], today: CalendarDay) -> [CalendarDay: [Chip]] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let tasks = store.openTasks.filter { q.isEmpty || $0.title.localizedCaseInsensitiveContains(q) }
        var result: [CalendarDay: [Chip]] = [:]
        let first = months.first!, end = months.last!.adding(months: 1)
        for task in tasks {
            guard let due = task.dueDate, due >= first, due < end else { continue }
            result[due, default: []].append(Chip(id: "t" + task.id, title: task.parts.title,
                                                 kind: due < today ? .overdue : .task, sort: task.timeMinutes ?? 2000))
        }
        for preview in RecurrenceRules.previews(tasks, today: today, months: Set(months)) {
            result[preview.date, default: []].append(Chip(id: preview.id, title: preview.task.parts.title,
                                                          kind: .preview, sort: preview.task.timeMinutes ?? 2000))
        }
        if q.isEmpty {
            for event in store.calendarFeed.events where event.date >= first && event.date < end {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: event.start)
                result[event.date, default: []].append(Chip(id: "e" + event.id, title: event.title, kind: .event,
                                                            sort: event.allDay ? 3000 : 3000 + (parts.hour ?? 0) * 60 + (parts.minute ?? 0)))
            }
        }
        return result.mapValues { $0.sorted { ($0.sort, $0.title) < ($1.sort, $1.title) } }
    }
}

struct MonthGrid: View {
    let month: CalendarDay
    let today: CalendarDay
    let chips: [CalendarDay: [CalendarView.Chip]]
    let onSelect: (CalendarDay) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4, alignment: .top), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            ForEach(["S", "M", "T", "W", "T", "F", "S"].indices, id: \.self) { index in
                Text(["S", "M", "T", "W", "T", "F", "S"][index])
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
            }
            ForEach(0..<month.weekday, id: \.self) { _ in Color.clear.frame(height: 1) }
            ForEach(1...month.daysInMonth, id: \.self) { number in
                let day = CalendarDay(year: month.year, month: month.month, day: number)!
                DayCell(day: day, today: today, chips: chips[day] ?? [])
                    .onTapGesture { onSelect(day) }
            }
        }
    }
}

struct DayCell: View {
    let day: CalendarDay
    let today: CalendarDay
    let chips: [CalendarView.Chip]

    var body: some View {
        let isToday = day == today
        VStack(alignment: .leading, spacing: 3) {
            Text("\(day.day)")
                .font(.system(size: 12, weight: isToday ? .heavy : .semibold))
                .foregroundStyle(isToday ? Palette.accent : day < today ? Palette.muted.opacity(0.6) : Palette.foreground)
            ForEach(chips.prefix(3)) { chip in
                ChipView(chip: chip)
            }
            if chips.count > 3 {
                Text("+\(chips.count - 3)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.muted)
            }
        }
        .frame(maxWidth: .infinity, minHeight: day < today && chips.isEmpty ? 34 : 64, alignment: .topLeading)
        .padding(4)
        .background(isToday ? Palette.accentSurface : Palette.inset.opacity(day < today ? 0.4 : 1),
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if isToday { RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.accent, lineWidth: 1) }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(TaskGroups.format(day, "EEEE, MMMM d")), \(chips.count) items")
        .accessibilityAddTraits(.isButton)
    }
}

struct ChipView: View {
    let chip: CalendarView.Chip

    var body: some View {
        HStack(spacing: 3) {
            if chip.kind == .event {
                RoundedRectangle(cornerRadius: 1).fill(Palette.event).frame(width: 2)
            }
            Text(chip.title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(2)
                .foregroundStyle(chip.kind == .overdue ? Palette.red : Palette.muted)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(chip.kind == .preview ? Color.clear : Palette.taskSurface, in: RoundedRectangle(cornerRadius: 4))
        .overlay {
            if chip.kind == .preview {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Palette.border, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }
        .opacity(chip.kind == .preview ? 0.7 : 1)
    }
}

// One day's tasks and events, with a button to add another.
struct DaySheet: View {
    @EnvironmentObject private var store: TaskStore
    let day: CalendarDay
    let onEdit: (String) -> Void
    let onAdd: (CalendarDay?) -> Void

    var body: some View {
        let tasks = store.openTasks.filter { $0.dueDate == day }
        let events = store.calendarFeed.events.filter { $0.date == day }
        let previews = RecurrenceRules.previews(store.openTasks, today: store.today, months: [day.firstOfMonth])
            .filter { $0.date == day }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(TaskGroups.dayItems(tasks, events)) { item in
                        switch item {
                        case .task(let task):
                            TaskRow(task: task, overdue: day < store.today, onEdit: { onEdit(task.id) })
                        case .event(let event):
                            EventRow(event: event)
                        }
                    }
                    ForEach(previews, id: \.id) { preview in
                        HStack {
                            Image(systemName: "repeat")
                            Text(preview.task.parts.title)
                            Spacer()
                        }
                        .font(.taskNote)
                        .foregroundStyle(Palette.muted)
                        .padding(11)
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Palette.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                    if tasks.isEmpty && events.isEmpty && previews.isEmpty {
                        Text("Nothing on this day.")
                            .font(.taskNote)
                            .foregroundStyle(Palette.muted)
                            .padding(.vertical, 12)
                    }
                    Button("Add a task on this day", systemImage: "plus") { onAdd(day) }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                        .padding(.top, 8)
                }
                .padding(16)
            }
            .background(Palette.background)
            .navigationTitle(TaskGroups.format(day, "EEEE, MMM d"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
