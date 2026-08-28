import SwiftUI

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

/// Timeline, with Achievements alongside it rather than as a fifth tab.
///
/// They answer the same question — *what have I done* — and as peers they would compete for the
/// same intent. Timeline is the frequent one; Achievements is the reward you visit occasionally,
/// which makes it a segment rather than a destination.
struct TimelineTab: View {
    private enum Pane: String, CaseIterable { case history, achievements
        var title: String { self == .history ? "History" : "Achievements" }
    }
    @State private var pane: Pane = .history

    var body: some View {
        NavigationStack {
            Group {
                switch pane {
                case .history:      TimelineView(embedded: true)
                case .achievements: HighlightsView(embedded: true)
                }
            }
            // In the navigation bar, not the content.
            //
            // This started as a segmented control inset at the top of the content, which put two
            // of them on one screen: Timeline carries its own Years / Months / All along the
            // bottom, and the floating tab bar now crowds that. Two segmented controls competing
            // down a single screen is the reader having to work out which one they are arguing
            // with. The bar is the right home for the one that chooses *what you are looking at*;
            // the content keeps the one that chooses *how it is arranged*.
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $pane) {
                        ForEach(Pane.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
