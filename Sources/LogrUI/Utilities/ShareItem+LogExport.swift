import Logr

extension ShareItem {
    /// A share payload that serializes through the service when the user picks a destination, so a
    /// conformer overriding ``LogRService/exportLogs(format:includingPrivateValues:)`` (redaction, persisted
    /// history, …) produces the shared bytes.
    nonisolated static func logExport(from logr: any LogRService, format: ExportFormat) -> ShareItem {
        ShareItem(fileName: format.exportFileName, contentType: format.contentType) {
            try await logr.exportLogs(format: format)
        }
    }
}

extension ExportFormat {
    nonisolated var exportFileName: String {
        "logs.\(fileExtension)"
    }
}
