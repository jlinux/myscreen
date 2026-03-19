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
    let initialBundleIdentifier: String?
    let onSelect: (AppBinding) -> Void
    let onCancel: () -> Void
    @State private var apps: [RunningApp] = []
    @State private var selectedApp: RunningApp?
    @State private var windows: [WindowController.BindableWindowInfo] = []
    @State private var searchText = ""

    private var filteredApps: [RunningApp] {
        if searchText.isEmpty { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(selectedApp == nil ? "Select App to Bind" : "Select Window to Bind")
                .font(.headline)
                .padding(.top, 12)

            if let selectedApp {
                HStack {
                    Button("Back") {
                        self.selectedApp = nil
                        windows = []
                    }
                    .buttonStyle(.link)
                    Spacer()
                    Text(selectedApp.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                if windows.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Text("No bindable windows found")
                            .font(.subheadline)
                        Text("Open the target window and try again.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List(windows) { window in
                        Button {
                            onSelect(
                                AppBinding(
                                    bundleIdentifier: selectedApp.id,
                                    displayName: selectedApp.name,
                                    windowIdentifier: window.identifier,
                                    windowTitle: window.title,
                                    windowSubrole: window.subrole,
                                    lastKnownFrame: WindowFrameSnapshot(frame: window.frame)
                                )
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(window.title)
                                    .lineLimit(1)
                                Text(windowSubtitle(for: window))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                List(filteredApps) { app in
                    Button {
                        selectApp(app)
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

        if let initialBundleIdentifier,
           selectedApp == nil,
           let app = apps.first(where: { $0.id == initialBundleIdentifier }) {
            selectApp(app)
        }
    }

    private func selectApp(_ app: RunningApp) {
        selectedApp = app
        windows = WindowController.bindableWindows(for: app.id)
    }

    private func windowSubtitle(for window: WindowController.BindableWindowInfo) -> String {
        let position = "\(Int(window.frame.origin.x)), \(Int(window.frame.origin.y))"
        let size = "\(Int(window.frame.width))x\(Int(window.frame.height))"
        if let subrole = window.subrole, !subrole.isEmpty {
            return "\(subrole) - \(position) - \(size)"
        }
        return "\(position) - \(size)"
    }
}
