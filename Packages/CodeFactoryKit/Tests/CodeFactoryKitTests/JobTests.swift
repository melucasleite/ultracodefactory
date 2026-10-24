import Foundation
import Testing
@testable import CodeFactoryKit

@Suite struct JobTests {
    @Test func idsAreTmuxSafe() throws {
        for _ in 0..<50 {
            let id = Job.newID()
            #expect(try Tmux.validate(session: "codefactory-\(id)") == "codefactory-\(id)")
        }
    }

    @Test(arguments: ["a.b", "a:b", "", "a b", "a;rm"])
    func rejectsUnsafeSessionNames(_ name: String) {
        #expect(throws: CardError.self) { try Tmux.validate(session: name) }
    }

    @Test func storePersistsAndReconcilesDeadProcesses() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "cf-jobs-\(UUID().uuidString).json")
        let store = JobStore(fileURL: url)
        // A PID that's certainly not our agent: started "before boot".
        try await store.add(Job(id: "job-1", project: "p", projectID: "p", prompt: "x", action: "create", mode: .headless,
                                startedAt: .distantPast, pid: 1))
        let jobs = await store.refresh(tmux: nil, executableName: "claude")
        #expect(jobs.first?.state == .completed)

        let reloaded = JobStore(fileURL: url)
        #expect(await reloaded.all().first?.state == .completed)
        try await reloaded.removeFinished()
        #expect(await reloaded.all().isEmpty)
    }
}
