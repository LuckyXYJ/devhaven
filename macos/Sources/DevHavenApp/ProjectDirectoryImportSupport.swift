import Foundation
import DevHavenCore

private enum SecurityScopedBookmarkImportError: LocalizedError {
    case bookmarkGenerationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .bookmarkGenerationFailed(message):
            message
        }
    }
}

enum ProjectDirectoryImportAction {
    case addDirectory
    case addProjects

    var diagnosticsAction: ProjectImportAction {
        switch self {
        case .addDirectory:
            .addDirectory
        case .addProjects:
            .addProjects
        }
    }
}

enum ProjectDirectoryImportSupport {
    @MainActor
    static func withSecurityScopedAccess(
        _ urls: [URL],
        action: ProjectDirectoryImportAction?,
        operation: @MainActor () async -> Void
    ) async {
        let accessedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
        ProjectImportDiagnostics.shared.recordSecurityScope(
            action: action?.diagnosticsAction,
            requestedCount: urls.count,
            grantedCount: accessedURLs.count
        )
        defer {
            for url in accessedURLs {
                url.stopAccessingSecurityScopedResource()
            }
        }
        await operation()
    }

    @MainActor
    static func performImport(
        urls: [URL],
        action: ProjectDirectoryImportAction,
        viewModel: NativeAppViewModel
    ) async {
        let paths = uniqueStandardizedPaths(from: urls)
        guard !paths.isEmpty else {
            return
        }

        ProjectImportDiagnostics.shared.recordImportAttempt(
            action: action.diagnosticsAction,
            paths: paths
        )

        do {
            let bookmarkRecordsByPath = try securityScopedBookmarkRecords(
                from: urls,
                action: action,
                requireBookmarks: viewModel.currentDistribution == .appStore
            )
            switch action {
            case .addDirectory:
                try await importDirectories(
                    paths: paths,
                    bookmarkRecordsByPath: bookmarkRecordsByPath,
                    viewModel: viewModel
                )
            case .addProjects:
                try await viewModel.addDirectProjects(
                    paths,
                    securityScopedBookmarks: paths.compactMap { bookmarkRecordsByPath[$0] }
                )
                viewModel.selectDirectory(.directProjects)
                ProjectImportDiagnostics.shared.recordSelectionApplied(
                    action: .addProjects,
                    filter: "direct-projects"
                )
            }
        } catch {
            let resolvedError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            ProjectImportDiagnostics.shared.recordFailure(
                action: action.diagnosticsAction,
                errorDescription: resolvedError
            )
            viewModel.errorMessage = resolvedError
        }
    }

    @MainActor
    private static func importDirectories(
        paths: [String],
        bookmarkRecordsByPath: [String: SecurityScopedBookmarkRecord],
        viewModel: NativeAppViewModel
    ) async throws {
        var importedPaths = [String]()
        var importErrors = [String]()

        for path in paths {
            do {
                try viewModel.addProjectDirectory(path, securityScopedBookmark: bookmarkRecordsByPath[path])
                importedPaths.append(path)
            } catch {
                let resolvedError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                importErrors.append(resolvedError)
            }
        }

        guard !importedPaths.isEmpty else {
            let errorDescription = importErrors.first ?? "未找到可导入的目录。"
            ProjectImportDiagnostics.shared.recordFailure(
                action: .addDirectory,
                errorDescription: errorDescription
            )
            viewModel.errorMessage = importErrors.joined(separator: "\n")
            return
        }

        try await viewModel.refreshProjectCatalog()
        if importedPaths.count == 1, let firstPath = importedPaths.first {
            viewModel.selectDirectory(.directory(firstPath))
            ProjectImportDiagnostics.shared.recordSelectionApplied(
                action: .addDirectory,
                filter: "directory:\(firstPath)"
            )
        } else {
            viewModel.selectDirectory(.all)
            ProjectImportDiagnostics.shared.recordSelectionApplied(
                action: .addDirectory,
                filter: "all"
            )
        }
        viewModel.errorMessage = importErrors.isEmpty ? nil : importErrors.joined(separator: "\n")
    }

    private static func uniqueStandardizedPaths(from urls: [URL]) -> [String] {
        var seenPaths = Set<String>()
        return urls.compactMap { url in
            let path = url.standardizedFileURL.path()
            guard !path.isEmpty, seenPaths.insert(path).inserted else {
                return nil
            }
            return path
        }
    }

    @MainActor
    private static func securityScopedBookmarkRecords(
        from urls: [URL],
        action: ProjectDirectoryImportAction,
        requireBookmarks: Bool
    ) throws -> [String: SecurityScopedBookmarkRecord] {
        var recordsByPath: [String: SecurityScopedBookmarkRecord] = [:]
        var failedPaths = [String]()

        for url in urls {
            let normalizedPath = url.standardizedFileURL.path()
            guard !normalizedPath.isEmpty else {
                continue
            }
            do {
                let bookmarkData = try url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                recordsByPath[normalizedPath] = SecurityScopedBookmarkRecord(
                    path: normalizedPath,
                    bookmarkDataBase64: bookmarkData.base64EncodedString()
                )
            } catch {
                failedPaths.append(normalizedPath)
            }
        }

        if requireBookmarks, !failedPaths.isEmpty {
            let errorDescription = failedPaths.count == 1
                ? "无法为目录生成沙盒授权：\(failedPaths[0])"
                : "以下目录无法生成沙盒授权：\n\(failedPaths.joined(separator: "\n"))"
            ProjectImportDiagnostics.shared.recordFailure(
                action: action.diagnosticsAction,
                errorDescription: errorDescription
            )
            throw SecurityScopedBookmarkImportError.bookmarkGenerationFailed(errorDescription)
        }

        return recordsByPath
    }
}
