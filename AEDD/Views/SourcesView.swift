import SwiftUI
import UniformTypeIdentifiers

struct SourcesView: View {
    @Binding var sources: [URL]
    @State private var dragOver = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Sources")
                    .font(.headline)
                    .padding(.horizontal)

                Spacer()

                if !sources.isEmpty {
                    Button("Clear") {
                        sources = []
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                }
            }
            .padding(.top)

            if sources.isEmpty {
                VStack {
                    Spacer()

                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("Drop source folders here")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("Drag folders from mounted SMB shares")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
            } else {
                List {
                    ForEach(sources, id: \.self) { source in
                        SourceRowView(url: source) {
                            sources.removeAll { $0 == source }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $dragOver) { providers in
            handleDrop(providers: providers)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, error in
                if let data = data as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {

                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                       isDirectory.boolValue {
                        DispatchQueue.main.async {
                            if !sources.contains(url) {
                                sources.append(url)
                            }
                        }
                    }
                }
            }
        }
        return true
    }
}

struct SourceRowView: View {
    let url: URL
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "folder")
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.body)

                Text(url.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SourcesView(sources: .constant([
        URL(fileURLWithPath: "/Volumes/production_funcom/Projects/Game1"),
        URL(fileURLWithPath: "/Volumes/projects/Shared")
    ]))
}