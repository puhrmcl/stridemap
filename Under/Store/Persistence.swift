import Foundation

/// Where the state lives. The whole app is a few kilobytes of JSON, so it rides
/// in UserDefaults: no schema migrations, no container, nothing to break on a
/// simulator with no account signed in.
protocol StateStorage {
    func load() -> AppState?
    func save(_ state: AppState)
}

struct UserDefaultsStorage: StateStorage {
    static let key = "under.state.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppState? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(AppState.self, from: data)
    }

    func save(_ state: AppState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

/// Used by previews and by anyone who wants a throwaway store.
struct MemoryStorage: StateStorage {
    final class Box { var state: AppState? }
    private let box = Box()

    init(_ state: AppState? = nil) {
        box.state = state
    }

    func load() -> AppState? { box.state }
    func save(_ state: AppState) { box.state = state }
}
