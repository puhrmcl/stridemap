import SwiftUI
import UIKit

/// The user's profile avatar. Shows the photo they've chosen (stored as small JPEG data in app
/// storage, so it appears everywhere the avatar does — the map search bar, the profile header),
/// falling back to a caller-supplied placeholder when no photo has been set.
struct ProfileAvatar<Placeholder: View>: View {
    var size: CGFloat
    @ViewBuilder var placeholder: () -> Placeholder

    /// Shared key so a photo chosen on the profile page also shows on the map search bar.
    @AppStorage("profileImageData") private var profileImageData: Data?

    var body: some View {
        Group {
            if let data = profileImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
    }
}
