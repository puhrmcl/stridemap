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

    /// Tab glyphs, drawn for this bar rather than assembled from SF Symbols.
    ///
    /// SF Symbols are a set, but they are Apple's set: drawn to sit beside system text at the
    /// system's stroke weight, with each glyph solving its own problem. Picked one at a time they
    /// never quite become a family — `rectangle.grid.2x2` is a heavier drawing than `trophy`,
    /// which is heavier than `map`, and on a bar the width of a phone that reads as five icons
    /// that happen to be next to each other.
    ///
    /// These are five drawings on one grid: a 28pt box, a 1.7pt stroke, round caps and joins, the
    /// same optical margin on every side. That is what makes the modern bars — Nike's, the Apple
    /// Store's — look like one object rather than a row of borrowed pictures.
    ///
    /// They ship as vector assets with the template rendering intent, so the bar tints them for
    /// selection and appearance exactly as it does a system symbol.
    var image: String {
        switch self {
        case .map:          return "TabMap"
        case .timeline:     return "TabTimeline"
        case .achievements: return "TabAchievements"
        case .studio:       return "TabStudio"
        case .bag:          return "TabBag"
        case .search:       return "TabSearch"
        }
    }

    /// The SF Symbol equivalent, for the places outside the bar that draw a tab's glyph inline
    /// with text — the search sheet's scope chip, for one. A 28pt outline drawn for a tab bar is
    /// the wrong weight beside an 11pt label, and a symbol scales with the type where an image
    /// does not.
    var symbol: String {
        switch self {
        case .map:          return "map"
        case .timeline:     return "square.grid.2x2"
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

    /// The selection, with a re-tap turned into a signal.
    ///
    /// A `TabView` binding is written on every tap, including one that does not change the
    /// selection — which is the only place that gesture can be observed, since by the time a page
    /// sees it nothing about the state has moved. The write still happens either way; the extra
    /// line is the announcement.
    private var selection: Binding<EtchTab> {
        Binding(
            get: { appModel.selectedTab },
            set: { tapped in
                if tapped == appModel.selectedTab { appModel.reselect(tapped) }
                appModel.selectedTab = tapped
            }
        )
    }

    var body: some View {
        TabView(selection: selection) {
            Tab(EtchTab.map.title, image: EtchTab.map.image, value: EtchTab.map) {
                HomeView()
            }
            Tab(EtchTab.timeline.title, image: EtchTab.timeline.image, value: EtchTab.timeline) {
                TimelineTab()
            }
            Tab(EtchTab.achievements.title, image: EtchTab.achievements.image,
                value: EtchTab.achievements) {
                AchievementsTab()
            }
            Tab(EtchTab.studio.title, image: EtchTab.studio.image, value: EtchTab.studio) {
                StudioHomeView(isHome: true)
            }
            // The search glyph carries a sparkle, which is the convention every app that searches
            // across your own things has landed on. It is still `role: .search`, so the system
            // keeps drawing it detached from the other four — the relationship matters more than
            // the picture.
            Tab(EtchTab.search.title, image: EtchTab.search.image,
                value: EtchTab.search, role: .search) {
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
    @Environment(AppModel.self) private var appModel
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
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
                    //
                    // Nothing else lives up here. The gallery was briefly a glyph in this corner
                    // opening a full-screen cover, which made the photographs a side door off the
                    // page instead of one of its views. They are a fourth segment in the control
                    // below now, beside Years, Months and All, where the other three arrangements
                    // of the same history already are.
                    EtchPageHeader("Timeline", subtitle: visibleSpan ?? summary)
                        .padding(.bottom, 8)
                        .background(.bar)
                }
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// What the history amounts to — shown under the title until a scroll reports a date span,
    /// which is the more useful answer while you are moving through it.
    /// Derived from the scoped library, not the raw `@Query`, so a hikes-off / walks-off
    /// setting (or a Runs-only selector) cannot caption the page with types that are hidden.
    private var summary: String? {
        let scoped = runs.scoped(to: appModel.activityScope)
        guard !scoped.isEmpty else { return nil }
        let metres = scoped.reduce(0.0) { $0 + $1.distance }
        // Named from the history rather than fixed at "activities", so the header agrees with
        // the year cards directly beneath it. Found by looking at the render: a history of
        // nothing but runs printed "220 activities" over three cards each captioned "N runs",
        // which reads as two parts of one screen disagreeing about what they are counting.
        let count = "\(scoped.count) \(ActivityScope.noun(for: scoped))"
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
