import SwiftUI
import UniformTypeIdentifiers

struct DestinationView: View {
    @Binding var destination: URL?
    @State private var dragOver = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Destination")
                    .font(.headline)
                    .padding(.horizontal)

                Spacer()

                if destination != nil {
                    Button("Clear") {
                        destination = nil
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                }
            }
            .padding(.top)

            if let destination = destination {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "folder")
                            .foregroundColor(.accentColor)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(destination.lastPathComponent)
                                .font(.headline)

                            Text(destination.path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        Button("Choose...") {
                            chooseDestination()
                        }
                        .buttonStyle(.bordered)
                    }

                    if let volumeInfo = getVolumeInfo(for: destination) {
                        HStack {
                            Image(systemName: "internaldrive")
                                .foregroundColor(.secondary)

                            Text(volumeInfo)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .padding()
            } else {
                VStack {
                    Spacer()

                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("Drop a destination folder here")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("Must be on local disk or attached storage")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Choose Folder...") {
                            chooseDestination()
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(dragOver ? Color.accentColor : Color.secondary.opacity(0.3),
                               style: StrokeStyle(lineWidth: 2, dash: [5]))
                )
                .padding()
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $dragOver) { providers in
            handleDrop(providers: providers)
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Destination"

        if panel.runModal() == .OK {
            destination = panel.url
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, error in
            if let data = data as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {

                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    DispatchQueue.main.async {
                        destination = url
                    }
                }
            }
        }
        return true
    }

    private func getVolumeInfo(for url: URL) -> String? {
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .volumeNameKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeTotalCapacityKey
            ])

            guard let volumeName = resourceValues.volumeName else { return nil }

            var info = "Volume: \(volumeName)"

            if let available = resourceValues.volumeAvailableCapacityForImportantUsage,
               let total = resourceValues.volumeTotalCapacity {
                let availableGB = Double(available) / (1024 * 1024 * 1024)
                let totalGB = Double(total) / (1024 * 1024 * 1024)
                info += String(format: " • %.1f GB available of %.1f GB", availableGB, totalGB)
            }

            return info
        } catch {
            return nil
        }
    }
}

#Preview {
    Group {
        DestinationView(destination: .constant(nil))

        DestinationView(destination: .constant(URL(fileURLWithPath: "/Users/user/Desktop/CopyDestination")))
    }
}