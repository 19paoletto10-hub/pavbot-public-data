import Foundation

@MainActor
final class ReloadGate {
    private var runningKeys: Set<String> = []
    private var lastFinishedAtByKey: [String: Date] = [:]
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func begin(key: String, minimumInterval: TimeInterval = 0) -> Bool {
        guard !runningKeys.contains(key) else { return false }
        if minimumInterval > 0,
           let lastFinishedAt = lastFinishedAtByKey[key],
           now().timeIntervalSince(lastFinishedAt) < minimumInterval {
            return false
        }
        runningKeys.insert(key)
        return true
    }

    func finish(key: String) {
        runningKeys.remove(key)
        lastFinishedAtByKey[key] = now()
    }
}
