import SwiftUI

struct ShareSelectorView: View {
    @EnvironmentObject var smbManager: SMBManager
    @Environment(\.dismiss) var dismiss

    @State private var selectedShares: Set<SMBShare> = []
    @State private var isMounting = false

    let onMounted: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "externaldrive.connected.to.line.below")
                        .font(.title)
                        .foregroundColor(.accentColor)

                    Text("Select Shares to Mount")
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                Text("Choose one or more shares to mount as read-only volumes.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }

            if smbManager.availableShares.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No shares available")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("No mountable disk shares were found on the server.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                List(smbManager.availableShares, id: \.id, selection: $selectedShares) { share in
                    ShareRowView(
                        share: share,
                        isSelected: selectedShares.contains(share)
                    ) { isSelected in
                        if isSelected {
                            selectedShares.insert(share)
                        } else {
                            selectedShares.remove(share)
                        }
                    }
                }
                .listStyle(.plain)
                .frame(minHeight: 200, maxHeight: 300)
                .border(Color.secondary.opacity(0.3))
            }

            if isMounting {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Mounting selected shares...")
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Mount Selected (\(selectedShares.count))") {
                    mountSelectedShares()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedShares.isEmpty || isMounting)
            }
        }
        .padding(24)
        .frame(width: 500, height: 450)
    }

    private func mountSelectedShares() {
        guard !selectedShares.isEmpty else { return }

        isMounting = true

        let sharesToMount = Array(selectedShares)

        Task {
            do {
                try await smbManager.mountShares(sharesToMount)
                await MainActor.run {
                    onMounted()
                }
            } catch {
                print("Mount failed: \(error)")
            }
            await MainActor.run {
                isMounting = false
            }
        }
    }
}

struct ShareRowView: View {
    let share: SMBShare
    let isSelected: Bool
    let onSelectionChanged: (Bool) -> Void

    var body: some View {
        HStack {
            Button(action: {
                onSelectionChanged(!isSelected)
            }) {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .accentColor : .secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(share.name)
                            .font(.body)
                            .fontWeight(.medium)

                        HStack {
                            Text("Type: \(share.type)")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text("Will mount at: /Volumes/\(share.name)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ShareSelectorView(onMounted: {})
    .environmentObject({
        let manager = SMBManager()
        return manager
    }())
}