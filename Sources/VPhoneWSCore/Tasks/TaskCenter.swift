import Foundation
import Observation

@MainActor
@Observable
public final class TaskCenter {
    public private(set) var tasks: [TaskModel] = []
    private let runner: StreamingRunner

    public init(runner: StreamingRunner) {
        self.runner = runner
    }

    @discardableResult
    public func start(
        title: String, plannedStages: [String], stageMap: [String: String] = [:],
        executable: URL, arguments: [String]
    ) -> TaskModel {
        let model = TaskModel(title: title, plannedStages: plannedStages, stageMap: stageMap)
        tasks.insert(model, at: 0)
        Task { await model.run(executable: executable, arguments: arguments, runner: runner) }
        return model
    }
}
