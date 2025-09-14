import Foundation
import Combine

@MainActor
class JobManager: ObservableObject {
    @Published var jobs: [CopyJob] = []
    @Published var currentJobIndex: Int?

    private var jobQueue = OperationQueue()
    private var activeRsyncOperation: RsyncOperation?
    private var cancellables = Set<AnyCancellable>()

    init() {
        jobQueue.maxConcurrentOperationCount = 1
        jobQueue.qualityOfService = .utility
    }

    func addJob(_ job: CopyJob) {
        var newJob = job
        newJob.logURL = newJob.generateLogURL()
        jobs.append(newJob)

        if currentJobIndex == nil {
            processNextJob()
        }
    }

    func cancelJob(_ jobId: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobId }) else { return }
        var job = jobs[index]

        if job.state == .running {
            activeRsyncOperation?.cancel()
            job.state = .cancelled
            job.completedAt = Date()
            jobs[index] = job

            processNextJob()
        } else if job.state == .pending {
            job.state = .cancelled
            job.completedAt = Date()
            jobs[index] = job
        }
    }

    func retryJob(_ jobId: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobId }) else { return }
        var job = jobs[index]

        if job.state == .failed {
            job.state = .pending
            job.error = nil
            job.progress = 0.0
            job.startedAt = nil
            job.completedAt = nil
            jobs[index] = job

            if currentJobIndex == nil {
                processNextJob()
            }
        }
    }

    func moveJobs(from source: IndexSet, to destination: Int) {
        let jobsToMove = source.map { jobs[$0] }
        jobs.move(fromOffsets: source, toOffset: destination)

        if let currentIndex = currentJobIndex {
            if let movingJob = jobsToMove.first(where: { $0.state == .running }),
               let newIndex = jobs.firstIndex(where: { $0.id == movingJob.id }) {
                currentJobIndex = newIndex
            }
        }
    }

    func clearCompletedJobs() {
        jobs.removeAll { job in
            job.state.isFinished && job.state != .running
        }

        if let currentIndex = currentJobIndex {
            if currentIndex >= jobs.count {
                currentJobIndex = nil
                processNextJob()
            } else if let currentJob = jobs.indices.contains(currentIndex) ? jobs[currentIndex] : nil,
                      currentJob.state != .running {
                currentJobIndex = nil
                processNextJob()
            }
        }
    }

    private func processNextJob() {
        guard let nextJobIndex = jobs.firstIndex(where: { $0.state == .pending }) else {
            currentJobIndex = nil
            return
        }

        currentJobIndex = nextJobIndex
        var job = jobs[nextJobIndex]
        job.state = .running
        job.startedAt = Date()
        jobs[nextJobIndex] = job

        let rsyncOperation = RsyncOperation(job: job)
        activeRsyncOperation = rsyncOperation

        rsyncOperation.progressPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.updateJobProgress(jobId: job.id, progress: progress)
            }
            .store(in: &cancellables)

        rsyncOperation.completionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                self?.handleJobCompletion(jobId: job.id, result: result)
            }
            .store(in: &cancellables)

        jobQueue.addOperation(rsyncOperation)
    }

    private func updateJobProgress(jobId: UUID, progress: Double) {
        guard let index = jobs.firstIndex(where: { $0.id == jobId }) else { return }
        jobs[index].progress = progress
    }

    private func handleJobCompletion(jobId: UUID, result: Result<Void, Error>) {
        guard let index = jobs.firstIndex(where: { $0.id == jobId }) else { return }
        var job = jobs[index]

        job.completedAt = Date()

        switch result {
        case .success:
            job.state = .completed
        case .failure(let error):
            if case RsyncError.cancelled = error {
                job.state = .cancelled
            } else {
                job.state = .failed
                job.error = error.localizedDescription
            }
        }

        jobs[index] = job
        activeRsyncOperation = nil

        processNextJob()
    }
}