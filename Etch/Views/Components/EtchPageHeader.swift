import SwiftUI

/// One masthead, worn by every surface except the map.
///
/// Studio, Timeline and Bag each grew their own top row — a wordmark between two glyphs here, a
/// large navigation title there, a segmented control in the bar somewhere else — so moving
/// between tabs meant the heading changed shape as well as words. A tab bar makes that obvious in
/// a way separate screens never did: the bottom of the app is now identical everywhere, and the
/// top was the only thing still arguing.
///
/// One row: the mark leading, the page's title centred, the avatar trailing — the same three
/// slots, in the same places, as the map's pill. The map is still the exception in *form* (it is
/// a full-bleed surface whose controls float over the terrain, and a bar across the top would
/// cover the thing you came to look at) but not in geometry: both are built from
/// `EtchHeaderMetrics` and both centre through `EtchCenteredRow`, so the mark, the middle and the
/// avatar occupy identical positions on every tab and stop moving when you switch between them.
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
        EtchCenteredRow {
            EtchWordmark(height: EtchHeaderMetrics.mark)
        } center: {
            // The title sits on the row's centre line, at the size and in the slot the map's
            // totals occupy. That is the whole idea: four tabs, one row, and the only thing that
            // changes between them is the words in the middle.
            //
            // Small, deliberately. It was a 34pt bold largeTitle on its own line, which made the
            // heading the loudest thing on every page and pushed the identity row up into the
            // status bar. A page label does not need to shout on a screen you navigated to on
            // purpose — the tab bar already told you where you are.
            VStack(spacing: 0) {
                Text(title)
                    .font(.etch(.headline, weight: .etchMedium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let subtitle {
                    Text(subtitle)
                        .font(.etch(.caption2))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .multilineTextAlignment(.center)
        } trailing: {
            HStack(spacing: 10) {
                trailing()
                profileButton
            }
        }
        .frame(height: EtchHeaderMetrics.rowHeight)
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
