import Foundation

enum DevHavenAppResourceBundleLocator {
    static let resourceBundleName = "DevHavenNative_DevHavenApp.bundle"

    static func resolveResourceBundleURL(
        fileManager: FileManager = .default,
        mainBundle: Bundle = .main,
        allBundles: [Bundle] = Bundle.allBundles,
        allFrameworks: [Bundle] = Bundle.allFrameworks
    ) -> URL? {
        let candidates = candidateResourceBundleURLs(mainBundle: mainBundle)
            + allBundles.flatMap(candidateResourceBundleURLs(mainBundle:))
            + allFrameworks.flatMap(candidateResourceBundleURLs(mainBundle:))
        return candidates.uniquedByPath().first { fileManager.fileExists(atPath: $0.path) }
    }

    static func candidateResourceBundleURLs(mainBundle: Bundle = .main) -> [URL] {
        var candidates: [URL] = []
        if let resourceURL = mainBundle.resourceURL {
            candidates.append(resourceURL.appending(path: resourceBundleName, directoryHint: .isDirectory))
        }
        candidates.append(mainBundle.bundleURL.appending(path: resourceBundleName, directoryHint: .isDirectory))
        candidates.append(mainBundle.bundleURL.deletingLastPathComponent().appending(path: resourceBundleName, directoryHint: .isDirectory))
        return candidates.uniquedByPath()
    }
}

enum DevHavenAppResourceLocator {
    static let resourceBundleName = DevHavenAppResourceBundleLocator.resourceBundleName

    static func resolveGhosttyResourcesRootURL(
        fileManager: FileManager = .default,
        mainBundle: Bundle = .main,
        allBundles: [Bundle] = Bundle.allBundles,
        allFrameworks: [Bundle] = Bundle.allFrameworks
    ) -> URL? {
        let directCandidates = candidateDirectGhosttyResourceRootURLs(mainBundle: mainBundle)
            + allBundles.flatMap(candidateDirectGhosttyResourceRootURLs(mainBundle:))
            + allFrameworks.flatMap(candidateDirectGhosttyResourceRootURLs(mainBundle:))
        if let directURL = directCandidates.uniquedByPath().first(where: { rootURL in
            fileManager.fileExists(atPath: rootURL.appending(path: "ghostty", directoryHint: .isDirectory).path)
        }) {
            return directURL
        }

        let bundleURLs = DevHavenAppResourceBundleLocator.candidateResourceBundleURLs(mainBundle: mainBundle)
            + allBundles.flatMap(DevHavenAppResourceBundleLocator.candidateResourceBundleURLs(mainBundle:))
            + allFrameworks.flatMap(DevHavenAppResourceBundleLocator.candidateResourceBundleURLs(mainBundle:))

        return bundleURLs.uniquedByPath()
            .map { $0.appending(path: "GhosttyResources", directoryHint: .isDirectory) }
            .first { fileManager.fileExists(atPath: $0.appending(path: "ghostty", directoryHint: .isDirectory).path) }
    }

    static func resolveResourceBundle(
        fileManager: FileManager = .default,
        mainBundle: Bundle = .main,
        allBundles: [Bundle] = Bundle.allBundles,
        allFrameworks: [Bundle] = Bundle.allFrameworks
    ) -> Bundle? {
        guard let bundleURL = DevHavenAppResourceBundleLocator.resolveResourceBundleURL(
            fileManager: fileManager,
            mainBundle: mainBundle,
            allBundles: allBundles,
            allFrameworks: allFrameworks
        ) else {
            return nil
        }
        return Bundle(url: bundleURL)
    }

    static func resolveResourceURL(
        subdirectory: String,
        resource: String,
        withExtension fileExtension: String,
        fileManager: FileManager = .default,
        mainBundle: Bundle = .main,
        allBundles: [Bundle] = Bundle.allBundles,
        allFrameworks: [Bundle] = Bundle.allFrameworks
    ) -> URL? {
        guard let resourceBundle = resolveResourceBundle(
            fileManager: fileManager,
            mainBundle: mainBundle,
            allBundles: allBundles,
            allFrameworks: allFrameworks
        ) else {
            return nil
        }

        if let resourceURL = resourceBundle.url(
            forResource: resource,
            withExtension: fileExtension,
            subdirectory: subdirectory
        ) {
            return resourceURL
        }

        let directURL = resourceBundle.bundleURL
            .appending(path: subdirectory, directoryHint: .isDirectory)
            .appending(path: "\(resource).\(fileExtension)", directoryHint: .notDirectory)
        guard fileManager.fileExists(atPath: directURL.path) else {
            return nil
        }
        return directURL
    }

    static func resolveAgentResourcesURL(
        fileManager: FileManager = .default,
        mainBundle: Bundle = .main,
        allBundles: [Bundle] = Bundle.allBundles,
        allFrameworks: [Bundle] = Bundle.allFrameworks
    ) -> URL? {
        let directCandidates = candidateDirectAgentResourceURLs(mainBundle: mainBundle)
            + allBundles.flatMap(candidateDirectAgentResourceURLs(mainBundle:))
            + allFrameworks.flatMap(candidateDirectAgentResourceURLs(mainBundle:))
        if let directURL = directCandidates.uniquedByPath().first(where: { fileManager.fileExists(atPath: $0.path) }) {
            return directURL
        }

        let bundleURLs = DevHavenAppResourceBundleLocator.candidateResourceBundleURLs(mainBundle: mainBundle)
            + allBundles.flatMap(DevHavenAppResourceBundleLocator.candidateResourceBundleURLs(mainBundle:))
            + allFrameworks.flatMap(DevHavenAppResourceBundleLocator.candidateResourceBundleURLs(mainBundle:))

        return bundleURLs.uniquedByPath()
            .map { $0.appending(path: "AgentResources", directoryHint: .isDirectory) }
            .first { fileManager.fileExists(atPath: $0.path) }
    }

    private static func candidateDirectAgentResourceURLs(mainBundle: Bundle = .main) -> [URL] {
        var candidates: [URL] = []
        if let resourceURL = mainBundle.resourceURL {
            candidates.append(resourceURL.appending(path: "AgentResources", directoryHint: .isDirectory))
        }
        candidates.append(mainBundle.bundleURL.appending(path: "Contents", directoryHint: .isDirectory).appending(path: "Resources", directoryHint: .isDirectory).appending(path: "AgentResources", directoryHint: .isDirectory))
        return candidates.uniquedByPath()
    }

    private static func candidateDirectGhosttyResourceRootURLs(mainBundle: Bundle = .main) -> [URL] {
        var candidates: [URL] = []
        if let resourceURL = mainBundle.resourceURL {
            candidates.append(resourceURL.appending(path: "GhosttyResources", directoryHint: .isDirectory))
        }
        candidates.append(mainBundle.bundleURL.appending(path: "Contents", directoryHint: .isDirectory).appending(path: "Resources", directoryHint: .isDirectory).appending(path: "GhosttyResources", directoryHint: .isDirectory))
        return candidates.uniquedByPath()
    }
}

private extension Array where Element == URL {
    func uniquedByPath() -> [URL] {
        var seenPaths = Set<String>()
        return filter { seenPaths.insert($0.path).inserted }
    }
}
