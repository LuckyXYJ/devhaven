import Foundation

public enum DevHavenDistribution: String, Equatable, Sendable {
    case direct
    case appStore

    public static var current: DevHavenDistribution {
#if DEVHAVEN_APPSTORE
        .appStore
#else
        .direct
#endif
    }

    public var capabilities: DevHavenDistributionCapabilities {
        switch self {
        case .direct:
            return DevHavenDistributionCapabilities(
                distribution: self,
                supportsExternalUpdater: true,
                supportsWorkspaceRun: true,
                supportsAgentEnvironmentInjection: true,
                supportsCLIHelperInjection: true
            )
        case .appStore:
            return DevHavenDistributionCapabilities(
                distribution: self,
                supportsExternalUpdater: false,
                supportsWorkspaceRun: false,
                supportsAgentEnvironmentInjection: false,
                supportsCLIHelperInjection: false
            )
        }
    }
}

public struct DevHavenDistributionCapabilities: Equatable, Sendable {
    public let distribution: DevHavenDistribution
    public let supportsExternalUpdater: Bool
    public let supportsWorkspaceRun: Bool
    public let supportsAgentEnvironmentInjection: Bool
    public let supportsCLIHelperInjection: Bool

    public init(
        distribution: DevHavenDistribution,
        supportsExternalUpdater: Bool,
        supportsWorkspaceRun: Bool,
        supportsAgentEnvironmentInjection: Bool,
        supportsCLIHelperInjection: Bool
    ) {
        self.distribution = distribution
        self.supportsExternalUpdater = supportsExternalUpdater
        self.supportsWorkspaceRun = supportsWorkspaceRun
        self.supportsAgentEnvironmentInjection = supportsAgentEnvironmentInjection
        self.supportsCLIHelperInjection = supportsCLIHelperInjection
    }
}
