import Foundation

struct Job: Identifiable, Equatable, Sendable {
    enum Status: String, Equatable, Sendable {
        case running, done, failed, cancelled
    }

    var id: UUID
    var query: String
    var summary: String
    var status: Status
}

@MainActor
final class JobQueue: ObservableObject {
    static let shared = JobQueue()

    @Published private(set) var jobs: [Job] = []

    var runningCount: Int { jobs.filter { $0.status == .running }.count }

    func start(query: String, summary: String) -> UUID {
        let job = Job(id: UUID(), query: query, summary: summary, status: .running)
        jobs.insert(job, at: 0)
        if jobs.count > 30 { jobs = Array(jobs.prefix(30)) }
        return job.id
    }

    func finish(_ id: UUID, status: Job.Status, summary: String? = nil) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].status = status
        if let summary { jobs[index].summary = summary }
    }
}
