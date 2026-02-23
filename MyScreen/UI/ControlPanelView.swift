import SwiftUI

struct ControlPanelView: View {
    @ObservedObject var viewModel: ControlPanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "rectangle.split.2x1")
                    .foregroundColor(.accentColor)
                Text("MyScreen")
                    .font(.headline)
                Spacer()
            }

            Divider()

            // Display selector
            if viewModel.displays.count > 1 {
                HStack {
                    Text("Display")
                        .font(.subheadline)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { viewModel.selectedDisplayID ?? 0 },
                        set: { viewModel.selectDisplay($0) }
                    )) {
                        ForEach(viewModel.displays, id: \.displayID) { display in
                            Text(display.localizedName)
                                .tag(display.displayID)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }
            }

            // Active toggle
            Toggle("Enable Reserved Area", isOn: Binding(
                get: { viewModel.isActive },
                set: { _ in viewModel.toggleActive() }
            ))

            if viewModel.isActive {
                // Edge position
                HStack {
                    Text("Position")
                        .font(.subheadline)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { viewModel.edge },
                        set: { viewModel.setEdge($0) }
                    )) {
                        ForEach(EdgePosition.allCases, id: \.self) { edge in
                            Text(edge.rawValue.capitalized).tag(edge)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }

                // Size
                HStack {
                    Text("Size")
                        .font(.subheadline)
                    Spacer()
                    Picker("", selection: $viewModel.sizeType) {
                        Text("%").tag("percentage")
                        Text("px").tag("pixels")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 80)
                }

                HStack {
                    Slider(
                        value: $viewModel.sizeValue,
                        in: viewModel.sizeType == "percentage" ? 10...50 : 200...1000,
                        step: viewModel.sizeType == "percentage" ? 1 : 10
                    ) {
                        EmptyView()
                    } onEditingChanged: { editing in
                        if !editing { viewModel.applyChanges() }
                    }

                    Text(viewModel.sizeType == "percentage"
                        ? "\(Int(viewModel.sizeValue))%"
                        : "\(Int(viewModel.sizeValue))px")
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)
                }

                Divider()

                // Bound app
                HStack {
                    Text("Bound App")
                        .font(.subheadline)
                    Spacer()
                    if let app = viewModel.boundApp {
                        HStack(spacing: 4) {
                            Text(app.displayName)
                                .font(.caption)
                            Button {
                                viewModel.unbindApp()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button(viewModel.boundApp == nil ? "Select" : "Change") {
                        viewModel.showAppPicker = true
                    }
                    .controlSize(.small)
                }
            }

            Divider()

            // Hotkey hint
            HStack {
                Image(systemName: "command")
                Image(systemName: "option")
                Text("M — Toggle reserved area")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Quit button
            HStack {
                Spacer()
                Button("Quit MyScreen") {
                    NSApp.terminate(nil)
                }
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear { viewModel.refresh() }
        .sheet(isPresented: $viewModel.showAppPicker) {
            AppPickerView(
                onSelect: { viewModel.bindApp($0) },
                onCancel: { viewModel.showAppPicker = false }
            )
        }
    }
}
