import SwiftUI

/// Wraps a surface's content in a `NavigationStack` only when it's presented as its own sheet.
/// When `embedded` (pushed *inside* another `NavigationStack` — e.g. the map's Explore hub), it
/// returns the content directly, so there's a single nav bar and pages push/pop smoothly instead
/// of the sheet dismissing and re-presenting from the bottom.
@MainActor @ViewBuilder
func NavRoot<Content: View>(_ embedded: Bool, @ViewBuilder content: () -> Content) -> some View {
    if embedded {
        content()
    } else {
        NavigationStack { content() }
    }
}
