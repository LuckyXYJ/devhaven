import Foundation

@MainActor
public final class DisabledWorkspaceRunManager: WorkspaceRunManaging {
    public var onEvent: (@MainActor @Sendable (WorkspaceRunManagerEvent) -> Void)?

    private let message: String

    public init(message: String = "当前发行版本已禁用运行配置与外部命令执行。") {
        self.message = message
        self.onEvent = nil
    }

    public func start(_ request: WorkspaceRunStartRequest) throws -> WorkspaceRunSession {
        throw NSError(
            domain: "DevHavenCore.DisabledWorkspaceRunManager",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    public func stop(sessionID: String) {}

    public func stopAll(projectPath: String) {}
}
