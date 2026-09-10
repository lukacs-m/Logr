import Logr

struct LogViewerData: Sendable {
    let statistics: LogStatistics
    let shareItems: [ExportFormat: ShareItem]

    static func load(_ snapshot: [LogEntry], includeSharing: Bool) async throws -> Self {
        try Task.checkCancellation()
        let statistics = await LogStatisticsComputer.compute(from: snapshot)
        var items: [ExportFormat: ShareItem] = [:]
        if includeSharing, !snapshot.isEmpty {
            for format in ExportFormat.allCases {
                try Task.checkCancellation()
                let data = try await LogExporter.serialize(snapshot, format: format)
                items[format] = ShareItem(data: data, fileName: "logs.\(format.fileExtension)",
                                          contentType: format.contentType)
            }
        }
        try Task.checkCancellation()
        return Self(statistics: statistics, shareItems: items)
    }
}
