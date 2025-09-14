import SwiftUI

struct JobQueueView: View {
    @EnvironmentObject var jobManager: JobManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Job Queue")
                    .font(.headline)
                    .padding(.horizontal)

                Spacer()

                if !jobManager.jobs.isEmpty {
                    Button("Clear Completed") {
                        jobManager.clearCompletedJobs()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            if jobManager.jobs.isEmpty {
                VStack {
                    Spacer()

                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)

                        Text("No jobs in queue")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("Submit copy jobs to see them here")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(jobManager.jobs.enumerated()), id: \.element.id) { index, job in
                        JobRowView(
                            job: job,
                            index: index + 1,
                            canReorder: !job.state.isActive && index > (jobManager.currentJobIndex ?? -1),
                            onCancel: {
                                jobManager.cancelJob(job.id)
                            },
                            onRetry: {
                                jobManager.retryJob(job.id)
                            },
                            onOpenLog: {
                                if let logURL = job.logURL {
                                    NSWorkspace.shared.open(logURL)
                                }
                            },
                            onRevealInFinder: {
                                NSWorkspace.shared.activateFileViewerSelecting([job.destination])
                            }
                        )
                    }
                    .onMove { source, destination in
                        jobManager.moveJobs(from: source, to: destination)
                    }
                }
                .listStyle(.plain)
            }
        }
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .top
        )
    }
}

struct JobRowView: View {
    let job: CopyJob
    let index: Int
    let canReorder: Bool
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onOpenLog: () -> Void
    let onRevealInFinder: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(job.displayName)
                    .font(.body)
                    .fontWeight(.medium)

                HStack {
                    JobStatusBadge(state: job.state)

                    if job.state == .running {
                        ProgressView(value: job.progress, total: 1.0)
                            .frame(width: 100)
                    }

                    Spacer()

                    Text(job.formattedElapsedTime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if job.state == .running {
                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }

                if job.state == .failed {
                    Button("Retry") {
                        onRetry()
                    }
                    .buttonStyle(.bordered)
                }

                if job.logURL != nil {
                    Button("Log") {
                        onOpenLog()
                    }
                    .buttonStyle(.plain)
                }

                if job.state.isFinished {
                    Button("Reveal") {
                        onRevealInFinder()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
        .background(job.state == .running ? Color.accentColor.opacity(0.1) : Color.clear)
    }
}

struct JobStatusBadge: View {
    let state: JobState

    var body: some View {
        Text(state.rawValue)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(backgroundColorForState)
            .foregroundColor(foregroundColorForState)
            .cornerRadius(4)
    }

    private var backgroundColorForState: Color {
        switch state {
        case .pending:
            return Color.secondary.opacity(0.2)
        case .running:
            return Color.blue.opacity(0.2)
        case .completed:
            return Color.green.opacity(0.2)
        case .failed:
            return Color.red.opacity(0.2)
        case .cancelled:
            return Color.orange.opacity(0.2)
        }
    }

    private var foregroundColorForState: Color {
        switch state {
        case .pending:
            return .secondary
        case .running:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .orange
        }
    }
}

struct SubmitJobView: View {
    let sources: [URL]
    let destination: URL?
    let onSubmit: () -> Void

    var canSubmit: Bool {
        !sources.isEmpty && destination != nil
    }

    var body: some View {
        Button(action: onSubmit) {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Add to Queue")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canSubmit)
    }
}

#Preview {
    JobQueueView()
        .environmentObject(JobManager())
        .frame(height: 200)
}