import SwiftUI

/// One masthead, worn by every surface except the map.
///
/// Studio, Timeline and Bag each grew their own top row — a wordmark between two glyphs here, a
/// large navigation title there, a segmented control in the bar somewhere else — so moving
/// between tabs meant the heading changed shape as well as words. A tab bar makes that obvious in
/// a way separate screens never did: the bottom of the app is now identical everywhere, and the
/// top was the only thing still arguing.
///
/// Two rows: the mark and the avatar on the first, the page's title on the second. The map is
/// still the exception in *form* — it is a full-bleed surface whose controls float over the
/// terrain, and a bar across the top would cover the thing you came to look at — but no longer in
/// *geometry*: its pill is built from the same `EtchHeaderMetrics`, so the mark and the avatar
/// occupy identical positions on every tab and stop moving when you switch between them.
///
/// The profile button lives here rather than at each call site, so the avatar, its long-press to
/// clear the photo, and the sheet it opens are defined once and cannot drift apart.
struct EtchPageHeader<Trailing: View>: View {
    let title: String
    /// A quiet second line under the title — what this page is currently showing. Apple Photos
    /// puts the date you have scrolled to here; Timeline uses it for the size of the history.
    var subtitle: String?
    /// Anything the page wants between the title and the avatar — a count, a filter chip, an
    /// action that belongs to this page rather than to the app.
    @ViewBuilder var trailing: () -> Trailing

    @State private var showProfile = false
    @AppStorage("profileImageData") private var profileImageData: Data?

    init(_ title: String, subtitle: String? = nil,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Row one: identity. The mark and the avatar, at the geometry every tab shares —
            // including the map, whose floating pill is built from the same numbers. This row is
            // the reason the top of the app stops jumping when you change tabs: the two things
            // the eye tracks across the transition do not move, and only the row beneath them
            // changes.
            HStack(alignment: .center, spacing: 12) {
                EtchWordmark(height: EtchHeaderMetrics.mark)
                Spacer(minLength: 8)
                trailing()
                profileButton
            }
            .frame(height: EtchHeaderMetrics.rowHeight)

            // Row two: what this page is. Below the identity rather than beside it, so a long
            // title can never push the avatar out of position — the failure the fixed row exists
            // to prevent.
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.etch(.largeTitle, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(.etch(.subheadline))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, EtchHeaderMetrics.side)
        .padding(.top, EtchHeaderMetrics.top)
        .sheet(isPresented: $showProfile) { ProfileView() }
    }

    private var profileButton: some View {
        Button { showProfile = true } label: {
            ProfileAvatar(size: EtchHeaderMetrics.avatar) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: EtchHeaderMetrics.avatar))
                    // Quiet, like the map's. It is an empty slot, not a live signal.
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile")
        // Long-press clears the photo without a trip to the profile page.
        .contextMenu {
            if profileImageData != nil {
                Button(role: .destructive) { profileImageData = nil } label: {
                    Label("Remove Photo", systemImage: "trash")
                }
            }
        }
    }
}
