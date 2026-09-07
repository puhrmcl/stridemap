import SwiftUI
import SwiftData

struct PhotoMemoriesView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Query private var runs: [Run]
    @State private var now = Date()
    @State private var selectedRun: Run?
    @State private var saveError = false

    private var scope: ActivityScope { ActivitySettings.resolvedScope(appModel.activityScope, in: runs) }
    private var memories: [PhotoMemory] { PhotoMemories.onThisDay(in: runs, scope: scope, now: now) }
    private var hidden: [Run] { runs.scoped(to: scope).filter(\.isHiddenFromMemories) }

    var body: some View {
        @Bindable var appModel = appModel
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("On this day").font(.etch(.largeTitle, weight: .bold))
                    Text("Photos and activities from this date in your history. Browse filters don’t change these memories.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Menu {
                        Picker("Activity", selection: $appModel.activityScope) {
                            ForEach(ActivitySettings.visibleScopes) { value in Text(value.label).tag(value) }
                        }
                    } label: { Label(scope.label, systemImage: "line.3.horizontal.decrease") }

                    if memories.isEmpty {
                        ContentUnavailableView("No photo memories for today", systemImage: "photo.on.rectangle",
                            description: Text("Your history is still here in Timeline. Attach photos to past activities, or use Find Photos for All Activities in Settings."))
                    }
                    ForEach(memories) { memory in
                        VStack(alignment: .leading, spacing: 12) {
                            Button { selectedRun = memory.run } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    MemoryCover(identifiers: memory.run.memoryPhotoReferences)
                                    Text(memory.title).font(.etch(.title2, weight: .bold))
                                    Text(memory.run.name).font(.etch(.headline))
                                    Text("\(Format.date(memory.run.startDate)) · \(Format.distance(memory.run.distance))")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            HStack {
                                Text("Revisit the activity or add a note").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Menu {
                                    Button("Don’t show this memory again", systemImage: "eye.slash") {
                                        memory.run.isHiddenFromMemories = true
                                        memory.run.updatedAt = Date()
                                        save()
                                    }
                                } label: { Image(systemName: "ellipsis").padding(8) }
                                .accessibilityLabel("Memory options")
                            }
                        }
                    }
                    if !hidden.isEmpty {
                        DisclosureGroup("Hidden memories (\(hidden.count))") {
                            ForEach(hidden) { run in
                                HStack {
                                    Text(run.name).font(.subheadline)
                                    Spacer()
                                    Button("Restore") {
                                        run.isHiddenFromMemories = false
                                        run.updatedAt = Date()
                                        save()
                                    }
                                }.padding(.vertical, 8)
                            }
                        }
                    }
                }.padding(20)
            }
            .navigationTitle("Memories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .navigationDestination(item: $selectedRun) { RunDetailView(run: $0) }
            .onAppear { now = Date() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { now = Date() } }
            .task {
                // Re-evaluate across midnight as well as on foregrounding. No history mutation
                // is needed for a new day's memories to appear.
                while !Task.isCancelled {
                    let current = Date()
                    let next = Calendar.current.date(byAdding: .day, value: 1,
                        to: Calendar.current.startOfDay(for: current)) ?? current.addingTimeInterval(86400)
                    do { try await Task.sleep(for: .seconds(max(1, next.timeIntervalSince(current)))) }
                    catch { return }
                    now = Date()
                }
            }
            .alert("Couldn’t save memory changes", isPresented: $saveError) {
                Button("Retry") { save() }
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func save() { do { try context.save() } catch { saveError = true } }
}

private struct MemoryCover: View {
    let identifiers: [String]
    @State private var image: UIImage?
    @State private var loading = true
    var body: some View {
        Color.secondary.opacity(0.12)
            .frame(height: 230)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                else if loading { ProgressView() }
                else { Label("Photo unavailable", systemImage: "photo").foregroundStyle(.secondary) }
            }
            .clipShape(.rect(cornerRadius: 18))
            .task(id: identifiers) {
                image = nil
                loading = true
                for id in identifiers {
                    let loaded = await PhotoLibrary.image(for: id, targetSize: CGSize(width: 900, height: 600))
                    guard !Task.isCancelled else { return }
                    if let loaded { image = loaded; break }
                }
                loading = false
            }
    }
}
