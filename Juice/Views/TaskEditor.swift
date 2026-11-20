import SwiftUI

// Adds or edits a task. A date word typed into the title ("tomorrow", "friday", "dec 3")
// moves the task to that day and leaves the title, as on the website; "@5pm" sets a time.
struct TaskEditor: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss
    let target: EditorTarget

    @State private var title = ""
    @State private var notes = ""
    @State private var dueDate: CalendarDay?
    @State private var recurrence: Recurrence?
    @State private var showNotes = false
    @State private var pickingDate = false
    @State private var loaded = false
    // A date word already in an edited title is just part of its wording; only a newly
    // typed one moves the task.
    @State private var originalDateWord: String?
    @State private var confirmDelete = false
    @FocusState private var titleFocused: Bool

    private var editingID: String? {
        if case .edit(let id) = target { id } else { nil }
    }

    private var dateWord: DateWords.Match? {
        guard let match = DateWords.findInTitle(title, today: store.today),
              match.word.lowercased() != originalDateWord,
              !DateWords.remove(match, from: title).isEmpty else { return nil }
        return match
    }

    // The date it will be saved with.
    private var effectiveDate: CalendarDay? { dateWord?.date ?? dueDate }

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    titleField
                    if showNotes || !notes.isEmpty {
                        TextField("Notes", text: $notes, axis: .vertical)
                            .font(.taskNote)
                            .lineLimit(2...8)
                            .padding(12)
                            .background(Palette.inset, in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        Button("Add notes", systemImage: "text.alignleft") { showNotes = true }
                            .font(.meta)
                            .foregroundStyle(Palette.muted)
                    }
                    dateSection
                    repeatSection
                    if editingID != nil {
                        Button("Delete task", systemImage: "trash", role: .destructive) { confirmDelete = true }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.red)
                            .padding(.top, 8)
                    }
                }
                .padding(18)
            }
            .background(Palette.card)
            .navigationTitle(editingID == nil ? "New Task" : "Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingID == nil ? "Add" : "Save", action: save)
                        .fontWeight(.bold)
                        .disabled(!canSave)
                }
            }
            .confirmationDialog("Delete this task?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let editingID { store.delete(editingID) }
                    dismiss()
                }
            }
        }
        .onAppear(perform: load)
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("What needs doing?", text: $title, axis: .vertical)
                .font(.system(size: 20, weight: .semibold))
                .lineLimit(1...5)
                .focused($titleFocused)
                .submitLabel(.done)
                .onChange(of: title) { _, value in
                    // Return saves; a title is one line that wraps.
                    guard value.contains("\n") else { return }
                    title = value.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                    save()
                }
            if let dateWord {
                Label("“\(dateWord.word)” → \(TaskGroups.format(dateWord.date, "EEE, MMM d"))", systemImage: "calendar")
                    .font(.meta)
                    .foregroundStyle(Palette.accent)
                    .labelStyle(MetaLabelStyle())
            }
            if let time = TaskTime.label(for: title) {
                Label("At \(time)", systemImage: "clock")
                    .font(.meta)
                    .foregroundStyle(Palette.event)
                    .labelStyle(MetaLabelStyle())
            }
        }
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Date")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let today = store.today
                    chip("Today", selected: effectiveDate == today) { pick(today) }
                    chip("Tomorrow", selected: effectiveDate == today.adding(days: 1)) { pick(today.adding(days: 1)) }
                    let next = (8 - today.weekday) % 7
                    let monday = today.adding(days: next == 0 ? 7 : next)
                    chip("Next week", selected: effectiveDate == monday) { pick(monday) }
                    chip(customDateLabel(today), selected: isCustomDate(today), systemImage: "calendar") {
                        pickingDate.toggle()
                    }
                }
            }
            if pickingDate {
                DatePicker("Due date", selection: Binding(
                    get: { (effectiveDate ?? store.today).start() },
                    set: { pick(CalendarDay($0)) }
                ), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(Palette.accent)
            }
            if editingID != nil && effectiveDate == nil {
                Text("No date yet. It waits under Overdue until it gets one.")
                    .font(.meta)
                    .foregroundStyle(Palette.muted)
            }
        }
    }

    private var repeatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Repeat")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("Never", selected: recurrence == nil) { recurrence = nil }
                    ForEach(Recurrence.allCases) { option in
                        chip(option.label, selected: recurrence == option) { recurrence = option }
                    }
                }
            }
            .disabled(effectiveDate == nil)
            .opacity(effectiveDate == nil ? 0.5 : 1)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Palette.muted)
    }

    private func chip(_ label: String, selected: Bool, systemImage: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage) }
                Text(label)
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? Palette.background : Palette.foreground)
            .background(selected ? Palette.foreground : Palette.inset, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func isCustomDate(_ today: CalendarDay) -> Bool {
        guard let date = effectiveDate else { return false }
        let next = (8 - today.weekday) % 7
        return ![today, today.adding(days: 1), today.adding(days: next == 0 ? 7 : next)].contains(date)
    }

    private func customDateLabel(_ today: CalendarDay) -> String {
        guard isCustomDate(today), let date = effectiveDate else { return "Pick date" }
        return TaskGroups.format(date, date.year == today.year ? "EEE, MMM d" : "MMM d, yyyy")
    }

    // Picking a date replaces a typed date word's.
    private func pick(_ day: CalendarDay) {
        if let dateWord { title = DateWords.remove(dateWord, from: title) }
        dueDate = day
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch target {
        case .new(let day):
            dueDate = day ?? store.today
            titleFocused = true
        case .edit(let id):
            guard let task = store.task(id) else { return }
            title = task.title
            notes = task.notes
            dueDate = task.dueDate
            recurrence = task.recurrence
            originalDateWord = DateWords.findInTitle(task.title, today: store.today)?.word.lowercased()
        }
    }

    private func save() {
        guard canSave else { return }
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var date = dueDate
        if let dateWord {
            text = DateWords.remove(dateWord, from: text)
            date = dateWord.date
        }
        let repeats = date == nil ? nil : recurrence
        switch target {
        case .new:
            store.add(text, notes: notes, dueDate: date, recurrence: repeats, readDateWords: false)
        case .edit(let id):
            store.update(id, title: text, notes: notes, dueDate: date, recurrence: repeats)
        }
        dismiss()
    }
}
