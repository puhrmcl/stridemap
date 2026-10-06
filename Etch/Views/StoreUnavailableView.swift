import SwiftUI

/// Shown when the library on disk could not be opened.
///
/// The thing this screen exists to prevent is not the error — it is the two wrong responses to
/// it. Crashing on launch tells the user nothing and looks like the app is broken for everyone.
/// Quietly starting a fresh empty library looks like their history has been deleted, and on the
/// next sync it would be.
///
/// So: say plainly what happened, say that nothing has been lost, and give them the one action
/// that is actually safe — leave it alone and let a fix reach them. Explicitly no "reset" button:
/// the only thing it could do is delete the file this screen is protecting.
struct StoreUnavailableView: View {
    let error: Error

    @State private var showsDetail = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.accent)

            Text("Your library didn't open")
                .font(.etch(.title2, weight: .bold))
                .multilineTextAlignment(.center)

            Text("Your activities are still on this device — Etch just couldn't read them this "
                 + "time. Please don't delete the app: that would remove the file we need to "
                 + "recover.")
                .font(.etch(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Text("Try reopening Etch. If it keeps happening, send the details below to support "
                 + "and we'll get it back.")
                .font(.etch(.footnote))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button {
                showsDetail.toggle()
            } label: {
                Label(showsDetail ? "Hide details" : "Show details",
                      systemImage: showsDetail ? "chevron.up" : "chevron.down")
                    .font(.etch(.footnote, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)

            if showsDetail {
                ScrollView {
                    Text(detail)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 180)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
                .padding(.horizontal, 24)

                ShareLink(item: detail) {
                    Label("Share details", systemImage: "square.and.arrow.up")
                        .font(.etch(.footnote, weight: .semibold))
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Everything a support conversation needs and nothing it does not: the build, and what the
    /// store actually said. No activity data — a diagnostic someone is asked to share should not
    /// carry their history in it.
    private var detail: String {
        """
        Etch \(AppInfo.label)
        Store failed to open.
        \(String(describing: error))
        """
    }
}
