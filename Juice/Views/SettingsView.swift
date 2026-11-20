import AppIntents
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ThemeChoice.storageKey) private var theme = ThemeChoice.system

    @State private var calendarLink = ""
    @State private var calendarError: String?
    @State private var savingCalendar = false

    var body: some View {
        NavigationStack {
            Form {
                syncSection
                calendarSection
                Section("Siri & Shortcuts") {
                    SiriTipView(intent: AddTaskIntent())
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Say “Add a task in Juice”, then the task. Dates and times in it work as when typing: “call mom tomorrow @5pm”.")
                        Text("Also: “What's due today in Juice” and “Complete *task* in Juice”.")
                    }
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    ShortcutsLink()
                        .shortcutsLinkStyle(.automaticOutline)
                }
                Section("Appearance") {
                    Picker("Theme", selection: $theme) {
                        ForEach(ThemeChoice.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section {
                    Link("Juice on the web", destination: URL(string: "https://juice.tinyk.ing/")!)
                } footer: {
                    Text("Sign in there with the same Apple Account to see these tasks.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { calendarLink = store.calendarFeed.url }
        }
    }

    private var syncSection: some View {
        Section {
            HStack {
                Label(store.sync.isActive ? "iCloud" : "This iPhone only",
                      systemImage: store.sync.isActive ? "checkmark.icloud" : "icloud.slash")
                Spacer()
                if store.sync.busy { ProgressView() }
            }
            if !store.sync.status.isEmpty {
                Text(store.sync.status)
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
            }
            if let last = store.library.lastSync {
                LabeledContent("Last synced", value: last.formatted(.relative(presentation: .named)))
            }
            Button("Sync Now") {
                Task { await store.sync.syncNow() }
            }
            .disabled(store.sync.busy)
        } header: {
            Text("Sync")
        } footer: {
            Text("Tasks sync through your iCloud, privately, with your other devices and Juice on the web.")
        }
    }

    private var calendarSection: some View {
        Section {
            TextField("webcal:// or https:// link", text: $calendarLink)
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if let calendarError {
                Text(calendarError).font(.footnote).foregroundStyle(Palette.red)
            } else if case .failed(let message) = store.calendarFeed.status {
                Text(message).font(.footnote).foregroundStyle(Palette.red)
            }
            HStack {
                Button(store.calendarFeed.isOn ? "Update" : "Add Calendar") { saveCalendar(calendarLink) }
                    .disabled(savingCalendar || calendarLink.trimmingCharacters(in: .whitespaces).isEmpty
                              || calendarLink == store.calendarFeed.url)
                if savingCalendar || store.calendarFeed.status == .loading { ProgressView().padding(.leading, 8) }
            }
            if store.calendarFeed.isOn {
                if let fetched = store.calendarFeed.fetchedAt {
                    LabeledContent("Events", value: "\(store.calendarFeed.events.count), updated \(fetched.formatted(.relative(presentation: .named)))")
                }
                Button("Refresh") { Task { await store.calendarFeed.refresh() } }
                Button("Remove Calendar", role: .destructive) {
                    calendarLink = ""
                    saveCalendar("")
                }
            }
        } header: {
            Text("Calendar")
        } footer: {
            Text("Paste a calendar's subscription (.ics) link to see its events beside your tasks. It stays on this iPhone.")
        }
    }

    private func saveCalendar(_ link: String) {
        calendarError = nil
        savingCalendar = true
        Task {
            defer { savingCalendar = false }
            do {
                try await store.calendarFeed.setURL(link)
            } catch {
                calendarError = error.localizedDescription
            }
        }
    }
}
