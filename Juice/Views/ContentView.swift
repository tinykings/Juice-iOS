import SwiftUI

// What the add/edit sheet is for.
enum EditorTarget: Identifiable, Equatable {
    case new(CalendarDay?)
    case edit(String)

    var id: String {
        switch self {
        case .new(let day): "new:\(day?.description ?? "")"
        case .edit(let id): "edit:\(id)"
        }
    }
}

// The list, or the calendar (from the footer, or by turning the phone sideways), with
// the footer bar and the undo toast.
struct ContentView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var editing: EditorTarget?
    @State private var showSettings = false
    @State private var searching = false
    @State private var query = ""
    @AppStorage("showCalendar") private var showCalendar = false

    private var calendarShown: Bool { showCalendar || verticalSizeClass == .compact }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            if calendarShown {
                CalendarView(query: query, onEdit: { editing = .edit($0) }, onAdd: { editing = .new($0) })
            } else {
                TaskListView(query: query, onEdit: { editing = .edit($0) }, onAdd: { editing = .new($0) })
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if let undo = store.undo {
                    UndoToast(undo: undo)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                FooterBar(searching: $searching, query: $query, calendarShown: calendarShown,
                          onToggleCalendar: { withAnimation(.snappy) { showCalendar.toggle() } },
                          onSettings: { showSettings = true },
                          onAdd: { editing = .new(nil) })
            }
            .animation(.snappy, value: store.undo)
        }
        .sheet(item: $editing) { target in
            TaskEditor(target: target)
                .environmentObject(store)
                .presentationDetents(target == .new(nil) ? [.medium, .large] : [.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(store)
        }
        .onChange(of: store.addRequested, initial: true) { _, requested in
            guard requested else { return }
            store.addRequested = false
            editing = .new(nil)
        }
    }
}

// MARK: - Footer

struct FooterBar: View {
    @EnvironmentObject private var store: TaskStore
    @Binding var searching: Bool
    @Binding var query: String
    let calendarShown: Bool
    let onToggleCalendar: () -> Void
    let onSettings: () -> Void
    let onAdd: () -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            if searching {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                    TextField("Search tasks", text: $query)
                        .focused($searchFocused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(Palette.inset, in: RoundedRectangle(cornerRadius: 10))
                Button("Cancel") {
                    query = ""
                    searching = false
                }
                .font(.body.weight(.semibold))
                .padding(.horizontal, 6)
            } else {
                iconButton("magnifyingglass", "Search") {
                    searching = true
                    searchFocused = true
                }
                iconButton("gearshape", "Settings", action: onSettings)
                    .overlay(alignment: .topTrailing) {
                        // A small mark when iCloud isn't syncing.
                        if !store.sync.isActive || store.library.pendingCount > 0 && !store.sync.busy {
                            Circle().fill(store.sync.isActive ? Palette.accent : Palette.red)
                                .frame(width: 7, height: 7)
                                .offset(x: -6, y: 6)
                        }
                    }
                iconButton(calendarShown ? "list.bullet" : "calendar", calendarShown ? "List" : "Calendar",
                           action: onToggleCalendar)
                Spacer()
                Button(action: onAdd) {
                    Image("AddTask")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add task")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.bar)
    }

    private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Palette.muted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}

struct UndoToast: View {
    @EnvironmentObject private var store: TaskStore
    let undo: TaskStore.Undo

    var body: some View {
        HStack {
            Text(undo.kind == .completed ? "Completed “\(undo.title)”" : "Deleted “\(undo.title)”")
                .lineLimit(1)
                .foregroundStyle(Palette.background)
            Spacer()
            Button("Undo") { store.undoLast() }
                .fontWeight(.bold)
                .foregroundStyle(Palette.background)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Palette.foreground, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 14)
    }
}
