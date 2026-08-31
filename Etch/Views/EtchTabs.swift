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
    case map, timeline, achievements, studio, bag, search
    var id: String { rawValue }

    /// The four that are destinations. `search` is excluded on purpose — see above; so is
    /// `bag`, which is now a button in Studio's header rather than a bar item. A bag belongs
    /// beside the thing you fill it from, and giving it a permanent quarter of the bar put a
    /// shopping basket at the same rank as the map on a screen most people open to look at
    /// where they have been.
    static var destinations: [EtchTab] { [.map, .timeline, .achievements, .studio] }

    var title: String {
        switch self {
        case .map:          return "Map"
        case .timeline:     return "Timeline"
        case .achievements: return "Achievements"
        case .studio:       return "Studio"
        case .bag:          return "Bag"
        case .search:       return "Search"
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
        case .map:          return "map"
        case .timeline:     return "rectangle.grid.2x2"
        case .achievements: return "trophy"
        case .studio:       return "photo"
        case .bag:          return "bag"
        case .search:       return "magnifyingglass"
        }
    }

    /// What searching means while standing here.
    ///
    /// The scope changes; the tool never does. A corner button that is search on three tabs and
    /// something else on the fourth is two buttons wearing one coat, and it destroys the muscle
    /// memory a fixed position exists to build.
    var searchPrompt: String {
        switch self {
        case .map:          return "Search places and activities"
        case .timeline:     return "Search your activities"
        case .achievements: return "Search your records"
        case .studio:       return "Search products and sizes"
        case .bag:          return "Search your orders"
        case .search:       return "Search"
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

    /// Drives the bag's badge.
    @State private var cart = CartStore.shared

    var body: some View {
        @Bindable var appModel = appModel
        TabView(selection: $appModel.selectedTab) {
            Tab(EtchTab.map.title, systemImage: EtchTab.map.symbol, value: EtchTab.map) {
                HomeView()
            }
            Tab(EtchTab.timeline.title, systemImage: EtchTab.timeline.symbol, value: EtchTab.timeline) {
                TimelineTab()
            }
            Tab(EtchTab.achievements.title, systemImage: EtchTab.achievements.symbol,
                value: EtchTab.achievements) {
                AchievementsTab()
            }
            Tab(EtchTab.studio.title, systemImage: EtchTab.studio.symbol, value: EtchTab.studio) {
                StudioHomeView(isHome: true)
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

/// Timeline, laid out on Apple Photos' model.
///
/// Photos gives the page one title, a quiet line saying what you are looking at, and exactly one
/// scope control — Years / Months / All — and nothing else competing. Achievements used to be a
/// button in this header; it is a tab of its own now, and a page should not carry a second door
/// to somewhere the bar already goes.
struct TimelineTab: View {
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    /// The date span of whatever Timeline currently has on screen, written by it as you scroll.
    @State private var visibleSpan: String?
    @State private var showGallery = false

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
                        photosButton
                    }
                    .padding(.bottom, 8)
                    .background(.bar)
                }
                .toolbar(.hidden, for: .navigationBar)
                .fullScreenCover(isPresented: $showGallery) { PhotoGalleryView() }
        }
    }

    /// The door to every photograph at once.
    ///
    /// It belongs on this page rather than on its own tab: the gallery is the same history in a
    /// different arrangement, the way Years, Months and All are — and the bar already carries four
    /// destinations, which is as many as a bar can hold before it stops being navigable.
    ///
    /// Hidden when there is nothing behind it. A door to an empty room is worse than no door.
    @ViewBuilder private var photosButton: some View {
        if hasPhotos {
            Button { showGallery = true } label: {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: EtchHeaderMetrics.avatar, height: EtchHeaderMetrics.avatar)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("All photos")
        }
    }

    private var hasPhotos: Bool { runs.contains { !$0.photoReferences.isEmpty } }

    /// What the history amounts to — shown under the title until a scroll reports a date span,
    /// which is the more useful answer while you are moving through it.
    private var summary: String? {
        guard !runs.isEmpty else { return nil }
        let metres = runs.reduce(0.0) { $0 + $1.distance }
        // Named from the history rather than fixed at "activities", so the header agrees with
        // the year cards directly beneath it. Found by looking at the render: a history of
        // nothing but runs printed "220 activities" over three cards each captioned "N runs",
        // which reads as two parts of one screen disagreeing about what they are counting.
        let count = "\(runs.count) \(ActivityScope.noun(for: runs))"
        return "\(count) · \(Format.distance(metres, decimals: 0))"
    }
}

/// Achievements, as its own destination.
///
/// It used to be a button in Timeline's header, on the reasoning that a tab is a poor home for
/// something you open a few times a year. That reasoning was about the *old* Achievements, which
/// counted records. It now counts cities, states, countries and parks as well — the answer to
/// "where have I been", which is the question this whole app is built around — and a door to that
/// buried in another page's corner was hiding the better half of the product.
///
/// The bar had room because the Bag left it for Studio's header, where a basket belongs beside
/// the thing that fills it.
struct AchievementsTab: View {
    var body: some View {
        NavigationStack {
            HighlightsView(embedded: true)
        }
    }
}

