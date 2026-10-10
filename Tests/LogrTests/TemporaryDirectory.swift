import Foundation

/// A fresh directory under the system temporary directory, deleted on release.
///
/// Held as a stored property of a suite, it gives every test its own directory: Swift Testing creates
/// a suite instance per test case and releases it when the test ends.
final class TemporaryDirectory: Sendable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LogrTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
