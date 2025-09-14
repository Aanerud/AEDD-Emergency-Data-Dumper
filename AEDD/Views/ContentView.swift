import SwiftUI

struct ContentView: View {
    @EnvironmentObject var jobManager: JobManager
    @EnvironmentObject var smbManager: SMBManager
    @EnvironmentObject var settingsManager: SettingsManager

    @State private var showingConnectionSheet = false
    @State private var showingShareSelector = false
    @State private var sources: [URL] = []
    @State private var destination: URL?

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView(
                showingConnectionSheet: $showingConnectionSheet,
                showingShareSelector: $showingShareSelector
            )

            HSplitView {
                VStack {
                    SourcesView(sources: $sources)
                        .frame(minWidth: 200)

                    Spacer()

                    SubmitJobView(
                        sources: sources,
                        destination: destination,
                        onSubmit: submitJob
                    )
                    .padding()
                }

                VStack {
                    DestinationView(destination: $destination)
                        .frame(minWidth: 200)

                    Spacer()
                }
            }
            .frame(minHeight: 300)

            JobQueueView()
                .frame(minHeight: 200)
        }
        .sheet(isPresented: $showingConnectionSheet) {
            ConnectionView(onConnected: { credentials in
                showingShareSelector = true
                showingConnectionSheet = false
            })
        }
        .sheet(isPresented: $showingShareSelector) {
            ShareSelectorView(onMounted: {
                showingShareSelector = false
            })
        }
    }

    private func submitJob() {
        guard !sources.isEmpty, let destination = destination else { return }

        let host = smbManager.mountedShares.first?.host ?? "Unknown"
        let rsyncFlags = settingsManager.settings.defaultRsyncFlags

        let job = CopyJob(
            serverHost: host,
            sources: sources,
            destination: destination,
            rsyncArgs: rsyncFlags.arguments,
            createdAt: Date()
        )

        jobManager.addJob(job)

        self.sources = []
        self.destination = nil
    }
}

#Preview {
    ContentView()
        .environmentObject(JobManager())
        .environmentObject(SMBManager())
        .environmentObject(SettingsManager())
}