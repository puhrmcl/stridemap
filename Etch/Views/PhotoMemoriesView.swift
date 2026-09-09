import SwiftUI
import SwiftData

struct PhotoMemoriesView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Query private var runs: [Run]
    @State private var now = Date()
    @State private var selectedRun: Run?
    @State private var saveError = false
    @StateObject private var location = MemoryLocationProvider()

    private var scope: ActivityScope { ActivitySettings.resolvedScope(appModel.activityScope, in: runs) }
    private var collection: PhotoMemories.Collection { PhotoMemories.discover(in: runs, scope: scope, now: now) }
    private var hidden: [Run] { runs.scoped(to: scope).filter(\.isHiddenFromMemories) }
    private var nearby: [PhotoMemory] {
        guard let fix = location.location else { return [] }
        return PhotoMemories.nearby(in: runs, scope: scope, location: fix)
    }

    var body: some View {
        @Bindable var appModel = appModel
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    Text(collection.heading).font(.etch(.largeTitle, weight: .bold))
                    Text(collection.detail).font(.subheadline).foregroundStyle(.secondary)
                    Menu {
                        Picker("Activity", selection: $appModel.activityScope) {
                            ForEach(ActivitySettings.visibleScopes) { value in Text(value.label).tag(value) }
                        }
                    } label: { Label(scope.label, systemImage: "line.3.horizontal.decrease") }
                    if collection.memories.isEmpty {
                        ContentUnavailableView("More memories ahead", systemImage: "clock.arrow.circlepath",
                            description: Text("No past activities are available for this activity type. Try All Activities, or add an activity to your history."))
                    }
                    ForEach(collection.memories) { memory in memoryCard(memory) }
                    nearbySection
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
                                    }.frame(minHeight: 44)
                                }
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

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider().padding(.vertical, 8)
            Label("Near you", systemImage: "location").font(.etch(.title2, weight: .bold))
            Text("Rediscover activities that started within 25 km of where you are now, across your history.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button { location.request() } label: {
                Label(location.location == nil ? "Find nearby memories" : "Refresh location", systemImage: "location.circle")
                    .frame(minHeight: 44)
            }.disabled(location.isLoading)
            if location.isLoading { ProgressView("Finding your location…") }
            if let message = location.message { Text(message).font(.subheadline).foregroundStyle(.secondary) }
            if location.denied {
                Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
            }
            if location.location != nil && nearby.isEmpty {
                Text("No past activities found within 25 km. Your date memories are still above.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(nearby) { memory in memoryCard(memory) }
            Text("Location is used once when you tap, matched on your device, and isn’t saved by Memories.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func memoryCard(_ memory: PhotoMemory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { selectedRun = memory.run } label: {
                VStack(alignment: .leading, spacing: 12) {
                    if memory.cover != nil {
                        MemoryCover(identifiers: memory.run.memoryPhotoReferences, run: memory.run)
                    } else {
                        MemoryRoute(run: memory.run)
                    }
                    Text(memory.title).font(.etch(.title2, weight: .bold))
                    Text(memory.run.name).font(.etch(.headline))
                    Text("\(Format.date(memory.run.startDate)) · \(Format.distance(memory.run.distance))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
            }.buttonStyle(.plain)
            HStack {
                Text("Revisit the activity or add a note").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Don’t show this memory again", systemImage: "eye.slash") {
                        memory.run.isHiddenFromMemories = true
                        memory.run.updatedAt = Date()
                        save()
                    }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                .accessibilityLabel("Memory options")
            }
        }
    }
    private func save() { do { try context.save() } catch { saveError = true } }
}

private struct MemoryCover: View {
    let identifiers: [String]
    let run: Run
    @State private var image: UIImage?
    @State private var loading = true
    var body: some View {
        Color.secondary.opacity(0.12)
            .frame(height: 230)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                else if loading { ProgressView() }
                else { MemoryRoute(run: run) }
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

private struct MemoryRoute: View {
    let run: Run
    var body: some View {
        ZStack {
            Theme.accent.opacity(0.08)
            if run.hasRoute {
                RouteShape(coordinates: run.coordinates)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .padding(30)
            } else {
                Label("\(Format.distance(run.distance)) remembered", systemImage: "clock.arrow.circlepath")
                    .font(.etch(.title3)).foregroundStyle(Theme.accent)
            }
        }.frame(height: 180).clipShape(.rect(cornerRadius: 18))
    }
}
