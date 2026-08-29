import SwiftUI

/// One masthead, worn by every surface except the map.
///
/// Studio, Timeline and Bag each grew their own top row — a wordmark between two glyphs here, a
/// large navigation title there, a segmented control in the bar somewhere else — so moving
/// between tabs meant the heading changed shape as well as words. A tab bar makes that obvious in
/// a way separate screens never did: the bottom of the app is now identical everywhere, and the
/// top was the only thing still arguing.
///
/// Title left, profile right, matching the Apple Store's own arrangement. The map is the
/// exception on purpose: it is a full-bleed surface whose controls float over the terrain, and a
/// bar across the top of it would cover the thing you came to look at.
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
        HStack(alignment: .center, spacing: 12) {
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
            Spacer(minLength: 8)
            trailing()
            profileButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .sheet(isPresented: $showProfile) { ProfileView() }
    }

    private var profileButton: some View {
        Button { showProfile = true } label: {
            ProfileAvatar(size: 34) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.accent)
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
