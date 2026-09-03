import SwiftUI

/// Names, solo or two, the spend rule, the reminder, and what a quiet day is.
/// That's it. There is no hiding a log from the other person.
struct SettingsView: View {
    @EnvironmentObject private var store: UnderStore
    @Environment(\.dismiss) private var dismiss

    @State private var confirmingDrop = false
    @State private var reminderDenied = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Names") {
                    ForEach(store.people) { person in
                        TextField("First name", text: nameBinding(person))
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }
                }

                Section("People") {
                    Picker("People", selection: peopleBinding) {
                        Text("Solo").tag(0)
                        Text("Two people").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section {
                    Toggle("Evening reminder", isOn: reminderBinding)
                    if store.state.reminder.isOn {
                        DatePicker("Time", selection: reminderTimeBinding, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Reminder")
                } footer: {
                    Text(reminderDenied
                         ? "Turn on notifications for Under in the iOS Settings app to get a reminder."
                         : "One nudge to mark your own day. Nothing is ever sent about the other person.")
                }

                Section {
                    NavigationLink("What counts") {
                        SpendRuleView()
                    }
                } footer: {
                    Text(SpendRule.quietDay)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .alert("Go solo?", isPresented: $confirmingDrop) {
                Button("Cancel", role: .cancel) { }
                Button("Go solo", role: .destructive) { store.removePartner() }
            } message: {
                Text(dropMessage)
            }
        }
    }

    // MARK: - Bindings

    private func nameBinding(_ person: Person) -> Binding<String> {
        Binding(get: { store.person(person.id)?.name ?? "" },
                set: { store.rename(person.id, to: $0) })
    }

    private var peopleBinding: Binding<Int> {
        Binding(get: { store.isCouple ? 1 : 0 },
                set: { value in
                    if value == 1 {
                        store.addPartner()
                    } else if store.isCouple {
                        confirmingDrop = true
                    }
                })
    }

    private var reminderBinding: Binding<Bool> {
        Binding(get: { store.state.reminder.isOn },
                set: { isOn in
                    guard isOn else {
                        store.setReminder(on: false)
                        reminderDenied = false
                        return
                    }
                    Reminder.requestAuthorization { granted in
                        store.setReminder(on: granted)
                        reminderDenied = !granted
                    }
                })
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(get: {
                    var components = DateComponents()
                    components.hour = store.state.reminder.hour
                    components.minute = store.state.reminder.minute
                    return Calendar.current.date(from: components) ?? Date()
                },
                set: { date in
                    let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                    store.setReminderTime(hour: components.hour ?? 21, minute: components.minute ?? 0)
                })
    }

    private var dropMessage: String {
        guard let partner = store.partner else {
            return "Under goes back to one person on this device."
        }
        return "\(store.displayName(partner))'s days are removed from this device. Yours stay."
    }
}

#if DEBUG
#Preview {
    SettingsView().environmentObject(UnderStore.previewCouple)
}
#endif
