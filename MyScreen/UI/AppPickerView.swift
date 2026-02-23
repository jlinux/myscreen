import SwiftUI
import AppKit

struct RunningApp: Identifiable, Hashable {
    let id: String  // bundleIdentifier
    let name: String
    let icon: NSImage

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: RunningApp, rhs: RunningApp) -> Bool {
        lhs.id == rhs.id
    }
}

struct AppPickerView: View {
    let onSelect: (AppBinding) -> Void
    let onCancel: () -> Void
    @State private var apps: [RunningApp] = []
    @State private var searchText = ""

    private var filteredApps: [RunningApp] {
        if searchText.isEmpty { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Select App to Bind")
                .font(.headline)
                .padding(.top, 12)

            TextField("Search...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            List(filteredApps) { app in
                Button {
                    onSelect(AppBinding(bundleIdentifier: app.id, displayName: app.name))
                } label: {
                    HStack {
                        Image(nsImage: app.icon)
                            .resizable()
                            .frame(width: 24, height: 24)
                        Text(app.name)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 280, height: 350)
        .onAppear { refreshApps() }
    }

    private func refreshApps() {
        let runningApps = NSWorkspace.shared.runningApplications
        apps = runningApps
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .compactMap { app -> RunningApp? in
                guard let bundleID = app.bundleIdentifier else { return nil }
                let name = app.localizedName ?? bundleID
                let icon = app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
                return RunningApp(id: bundleID, name: name, icon: icon)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
