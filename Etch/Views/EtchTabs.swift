import SwiftUI
import SwiftData

/// The app's four destinations.
///
/// Etch had these already; they were just hidden. `HubView.exploreSection` listed Timeline,
/// Achievements, Studio and Filter as a menu *inside the search sheet* — navigation in the one
/// place nobody looks for it — and `RootView` branched on a `studioIsHome` preference that made
/// every user pick which half of the app they got. A person who chose the map never saw the shop;
/// a person who chose the shop reached the map through a modal. Both got a smaller app than the
/// one underneath.
///
/// Search is deliberately not in this enum's ordinary cases. It is a tool, not a destination:
/// you search *in order to arrive somewhere*, and a search tab is somewhere you have to navigate
/// back out of. `.search` exists here only because `Tab(role: .search)` needs a selection value,
/// and the system draws it detached from the others — which is exactly the relationship.
enum EtchTab: String, Hashable, CaseIterable, Identifiable {
    case map, timeline, studio, bag, search
    var id: String { rawValue }

    /// The four that are destinations. `search` is excluded on purpose — see above.
    static var destinations: [EtchTab] { [.map, .timeline, .studio, .bag] }

    var title: String {
        switch self {
        case .map:      return "Map"
        case .timeline: return "Timeline"
        case .studio:   return "Studio"
        case .bag:      return "Bag"
        case .search:   return "Search"
        }
    }

    /// Tab glyphs, chosen to sit together rather than one at a time.
    ///
    /// Studio stays a canvas — the tab is where you *make* something, and a shopfront said only
    /// that you could buy one. `photo.artframe` was the wrong canvas though: a hard rectangle
    /// with a heavy frame, beside a rounded bag and a rounded map, on a bar whose whole look is
    /// soft capsules. `photo` is the same idea drawn minimally, with the rounded corners the rest
    /// of the set has.
    var symbol: String {
        switch self {
        case .map:      return "map"
        case .timeline: return "rectangle.grid.2x2"
        case .studio:   return "photo"
        case .bag:      return "bag"
        case .search:   return "magnifyingglass"
        }
    }

    /// What searching means while standing here.
    ///
    /// The scope changes; the tool never does. A corner button that is search on three tabs and
    /// something else on the fourth is two buttons wearing one coat, and it destroys the muscle
    /// memory a fixed position exists to build.
    var searchPrompt: String {
        switch self {
        case .map:      return "Search places and activities"
        case .timeline: return "Search your activities"
        case .studio:   return "Search products and sizes"
        case .bag:      return "Search your orders"
        case .search:   return "Search"
        }
    }
}

/// The app's spine.
///
/// Four destinations on one bar, plus the system's detached search. On iOS 26 the bar draws
/// itself as the floating capsule the Nike and Apple Store apps use, with the search role sitting
/// apart from the others as its own circle; on earlier systems the same declaration renders as an
/// ordinary tab bar. Either way the structure is the same, which is why there is no availability
/// branch here — `Tab(value:role:)` is iOS 18, and only its *appearance* is newer.
///
/// The map is a tab rather than a `fullScreenCover` now, and that is not only tidiness: a cover is
/// torn down and rebuilt on every present, so the camera reset and the tiles were re-fetched each
/// time. Once the basemap is served from R2 that rebuild is a line on a bill, not just a stutter.
struct EtchTabView: View {
    @Environment(AppModel.self) private var appModel

    /// The last destination, for search to borrow its scope from. `.search` is not a place you
    /// were looking at anything, so it never becomes the scope.
    @State private var lastDestination: EtchTab = .map

    var body: some View {
        @Bindable var appModel = appModel
        TabView(selection: $appModel.selectedTab) {
            Tab(EtchTab.map.title, systemImage: EtchTab.map.symbol, value: EtchTab.map) {
                HomeView()
            }
            Tab(EtchTab.timeline.title, systemImage: EtchTab.timeline.symbol, value: EtchTab.timeline) {
                TimelineTab()
            }
            Tab(EtchTab.studio.title, systemImage: EtchTab.studio.symbol, value: EtchTab.studio) {
                StudioHomeView(isHome: true)
            }
            Tab(EtchTab.bag.title, systemImage: EtchTab.bag.symbol, value: EtchTab.bag) {
                BagView()
            }
            Tab(value: EtchTab.search, role: .search) {
                ScopedSearchView(scope: lastDestination)
            }
        }
        .onAppear {
            lastDestination = appModel.selectedTab == .search ? .map : appModel.selectedTab
            // CI preview only: "tabs" with ETCH_PREVIEW_SCROLL=studio opens the shell on that
            // tab, so each destination can be photographed with the bar in place. Inert without
            // the variable, the same as Studio's section anchors.
            if let named = ProcessInfo.processInfo.environment["ETCH_PREVIEW_SCROLL"],
               let tab = EtchTab(rawValue: named) {
                appModel.selectedTab = tab
            }
        }
        .onChange(of: appModel.selectedTab) { _, new in
            if new != .search { lastDestination = new }
        }
    }
}

/// Timeline, laid out on Apple Photos' model, with Achievements reachable from its header.
///
/// Photos gives the page one title, a quiet line saying what you are looking at, and exactly one
/// scope control — Years / Months / All — and nothing else competing. Etch's Timeline had grown
/// two controls because Achievements was made half of a segmented pair it was never parallel to:
/// Years, Months and All are three arrangements of one thing, and Achievements is a different
/// thing. It is an action in the header now, which is where a page keeps the door to somewhere
/// else.
///
/// It is still not a fifth tab. Timeline is the frequent destination; Achievements is the reward
/// you visit occasionally, and a tab is a poor home for something you open a few times a year.
struct TimelineTab: View {
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @State private var showAchievements = false
    /// The date span of whatever Timeline currently has on screen, written by it as you scroll.
    @State private var visibleSpan: String?

    var body: some View {
        NavigationStack {
            TimelineView(embedded: true, visibleSpan: $visibleSpan)
                // Header only. Timeline supplies its own Years / Months / All directly beneath,
                // and that is the page's single scope control.
                //
                // It was briefly two: History / Achievements here, and Years / Months / All at
                // the foot. Apple Photos — the model this page follows — has exactly one, docked
                // at the bottom because Photos has no tab bar. Etch does, so the control comes up
                // here instead, and Achievements stops being half of a segmented control it was
                // never parallel to. Years, Months and All are three arrangements of one thing;
                // Achievements is a different thing.
                .safeAreaInset(edge: .top, spacing: 0) {
                    // The span while scrolling, the summary otherwise — Photos shows where you
                    // are when there is a where, and what you have when there isn't.
                    EtchPageHeader("Timeline", subtitle: visibleSpan ?? summary) {
                        Button { showAchievements = true } label: {
                            Image(systemName: "trophy")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 34, height: 34)
                                .background(Theme.accent.opacity(0.12), in: .circle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Achievements")
                    }
                    .padding(.bottom, 8)
                    .background(.bar)
                }
                .toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: $showAchievements) {
                    NavigationStack {
                        HighlightsView(embedded: true)
                            .navigationTitle("Achievements")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Done") { showAchievements = false }
                                }
                            }
                    }
                }
        }
    }

    /// What the history amounts to — shown under the title until a scroll reports a date span,
    /// which is the more useful answer while you are moving through it.
    private var summary: String? {
        guard !runs.isEmpty else { return nil }
        let metres = runs.reduce(0.0) { $0 + $1.distance }
        let count = runs.count == 1 ? "1 activity" : "\(runs.count) activities"
        return "\(count) · \(Format.distance(metres, decimals: 0))"
    }
}
