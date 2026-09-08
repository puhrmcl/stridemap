import SwiftUI

/// Value history shared by both editors. A burst of typing/slider changes is one undo step.
struct StudioEditHistory<Value: Equatable> {
    private(set) var past: [Value] = []
    private(set) var future: [Value] = []
    private var current: Value?
    private var lastEdit = Date.distantPast
    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    mutating func record(from before: Value, to after: Value, at date: Date = Date()) {
        guard before != after, current != after else { return }
        let coalesces = future.isEmpty && !past.isEmpty && (0..<0.45).contains(date.timeIntervalSince(lastEdit))
        if !coalesces { past.append(before) }
        if past.count > 60 { past.removeFirst(past.count - 60) }
        future.removeAll()
        current = after
        lastEdit = date
    }

    mutating func undo(_ value: Value) -> Value? {
        guard let previous = past.popLast() else { return nil }
        future.append(value)
        current = previous
        lastEdit = .distantPast
        return previous
    }

    mutating func redo(_ value: Value) -> Value? {
        guard let next = future.popLast() else { return nil }
        past.append(value)
        current = next
        lastEdit = .distantPast
        return next
    }
}

/// A neutral viewing surface: the paper keeps its real square corners and complete proportions.
struct StudioArtworkStage: View {
    let image: UIImage?
    let aspect: CGFloat
    let updating: Bool
    let failed: Bool
    let inspect: () -> Void
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geometry in
                let room = CGSize(width: max(1, geometry.size.width - 48),
                                  height: max(1, geometry.size.height - 20))
                let ratio = image.map { $0.size.width / max(1, $0.size.height) } ?? aspect
                let width = min(room.width, room.height * max(0.1, ratio))
                ZStack {
                    Rectangle().fill(Theme.Brand.galleryWhite)
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                    } else if !failed {
                        ProgressView("Composing your print…").font(.footnote)
                    }
                }
                .frame(width: width, height: width / max(0.1, ratio))
                .overlay { Rectangle().strokeBorder(.black.opacity(0.08), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.12), radius: 14, y: 7)
                .contentShape(.rect)
                .onTapGesture { if image != nil { inspect() } }
                .accessibilityLabel("Artwork preview")
                .accessibilityHint("Opens a full screen view with zoom")
                .accessibilityAddTraits(.isButton)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            HStack(spacing: 8) {
                if failed {
                    Text("Preview couldn’t update").foregroundStyle(.secondary)
                    Button("Try again", action: retry)
                } else if updating {
                    ProgressView().controlSize(.mini)
                    Text("Updating preview…").foregroundStyle(.secondary)
                } else {
                    Button(action: inspect) {
                        Label("View artwork", systemImage: "arrow.up.left.and.arrow.down.right")
                    }.disabled(image == nil)
                }
            }
            .font(.etch(.caption))
            .frame(minHeight: 26)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
