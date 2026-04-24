import Foundation

public struct SecurityScopedBookmarkRestoreResult: Sendable {
    public let records: [SecurityScopedBookmarkRecord]
    public let inaccessiblePaths: [String]

    public init(records: [SecurityScopedBookmarkRecord], inaccessiblePaths: [String]) {
        self.records = records
        self.inaccessiblePaths = inaccessiblePaths
    }
}

public final class SecurityScopedBookmarkManager {
    private var activeURLsByPath: [String: URL] = [:]

    public init() {}

    deinit {
        stopAccess(for: Array(activeURLsByPath.keys))
    }

    @discardableResult
    public func restoreAccess(from records: [SecurityScopedBookmarkRecord]) -> SecurityScopedBookmarkRestoreResult {
        var restoredRecords = [SecurityScopedBookmarkRecord]()
        var inaccessiblePaths = [String]()

        for record in records {
            let normalizedPath = normalizeSecurityScopedBookmarkPath(record.path)
            guard let bookmarkData = Data(base64Encoded: record.bookmarkDataBase64) else {
                inaccessiblePaths.append(normalizedPath)
                restoredRecords.append(SecurityScopedBookmarkRecord(path: normalizedPath, bookmarkDataBase64: record.bookmarkDataBase64))
                continue
            }

            do {
                var isStale = false
                let resolvedURL = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ).standardizedFileURL
                _ = activateResolvedURL(resolvedURL, path: normalizedPath)

                let nextRecord: SecurityScopedBookmarkRecord
                if isStale,
                   let refreshedRecord = makeRecord(for: resolvedURL, path: normalizedPath) {
                    nextRecord = refreshedRecord
                } else {
                    nextRecord = SecurityScopedBookmarkRecord(path: normalizedPath, bookmarkDataBase64: record.bookmarkDataBase64)
                }
                restoredRecords.append(nextRecord)
            } catch {
                inaccessiblePaths.append(normalizedPath)
                restoredRecords.append(SecurityScopedBookmarkRecord(path: normalizedPath, bookmarkDataBase64: record.bookmarkDataBase64))
            }
        }

        return SecurityScopedBookmarkRestoreResult(
            records: deduplicatedSecurityScopedBookmarkRecords(restoredRecords),
            inaccessiblePaths: inaccessiblePaths.sorted()
        )
    }

    @discardableResult
    public func activate(records: [SecurityScopedBookmarkRecord]) -> [String] {
        records.compactMap { record in
            let normalizedPath = normalizeSecurityScopedBookmarkPath(record.path)
            guard let bookmarkData = Data(base64Encoded: record.bookmarkDataBase64) else {
                return nil
            }

            do {
                var isStale = false
                let resolvedURL = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ).standardizedFileURL
                return activateResolvedURL(resolvedURL, path: normalizedPath) ? normalizedPath : nil
            } catch {
                return nil
            }
        }
    }

    public func stopAccess(for paths: [String]) {
        for path in paths.map(normalizeSecurityScopedBookmarkPath) {
            guard let url = activeURLsByPath.removeValue(forKey: path) else {
                continue
            }
            url.stopAccessingSecurityScopedResource()
        }
    }

    public func makeRecord(for url: URL) -> SecurityScopedBookmarkRecord? {
        makeRecord(for: url, path: normalizeSecurityScopedBookmarkPath(url.standardizedFileURL.path))
    }

    private func makeRecord(for url: URL, path: String) -> SecurityScopedBookmarkRecord? {
        do {
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return SecurityScopedBookmarkRecord(
                path: path,
                bookmarkDataBase64: bookmarkData.base64EncodedString()
            )
        } catch {
            return nil
        }
    }

    private func activateResolvedURL(_ url: URL, path: String) -> Bool {
        if activeURLsByPath[path] != nil {
            return true
        }
        guard url.startAccessingSecurityScopedResource() else {
            return false
        }
        activeURLsByPath[path] = url
        return true
    }
}

private func normalizeSecurityScopedBookmarkPath(_ path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
}

private func deduplicatedSecurityScopedBookmarkRecords(_ records: [SecurityScopedBookmarkRecord]) -> [SecurityScopedBookmarkRecord] {
    var recordsByPath: [String: SecurityScopedBookmarkRecord] = [:]
    for record in records {
        let normalizedPath = normalizeSecurityScopedBookmarkPath(record.path)
        recordsByPath[normalizedPath] = SecurityScopedBookmarkRecord(
            path: normalizedPath,
            bookmarkDataBase64: record.bookmarkDataBase64
        )
    }
    return recordsByPath.values.sorted { $0.path < $1.path }
}
