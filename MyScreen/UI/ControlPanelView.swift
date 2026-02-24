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

            // Display picker
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

            // Brightness slider
            if viewModel.brightnessControlMethod != .unavailable {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "sun.min")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Slider(
                            value: Binding(
                                get: { viewModel.brightness },
                                set: { viewModel.setBrightness($0) }
                            ),
                            in: 0.05...1.0,
                            step: 0.01
                        )
                        Image(systemName: "sun.max")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("\(Int(viewModel.brightness * 100))%")
                            .monospacedDigit()
                            .font(.caption)
                            .frame(width: 35, alignment: .trailing)
                    }
                    if viewModel.brightnessControlMethod == .softwareGamma {
                        Text("Software dimming (hardware control unavailable)")
                            .font(.caption2)
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    }
                }
            }

            // Resolution section
            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.isResolutionExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.isResolutionExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 12)
                        Text("Resolution")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        if !viewModel.isResolutionExpanded, let mode = viewModel.currentDisplayMode {
                            Text(mode.dimensionLabel)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if mode.isHiDPI {
                                Text("HiDPI")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.blue))
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if viewModel.isResolutionExpanded {
                    ResolutionPickerView(
                        groups: viewModel.displayModeGroups,
                        currentMode: viewModel.currentDisplayMode,
                        onSelect: { viewModel.switchResolution(to: $0) }
                    )
                }
            }

            // Slots header
            HStack {
                Text("Reserved Areas")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Button {
                    viewModel.addSlot()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canAddSlot)
                .help(viewModel.canAddSlot ? "Add reserved area" : "All 4 edges used")
            }

            if viewModel.slots.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "rectangle.dashed")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("No reserved areas")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Click + to add one")
                            .font(.caption2)
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    }
                    .padding(.vertical, 8)
                    Spacer()
                }
            } else {
                ForEach(viewModel.slots) { slot in
                    SlotCardView(
                        slot: slot,
                        isExpanded: viewModel.expandedSlotID == slot.id,
                        usedEdges: viewModel.usedEdges(excluding: slot.id),
                        viewModel: viewModel
                    )
                }
            }

            Divider()

            // Hotkey
            HotkeyRecorderView(
                hotkeyConfig: $viewModel.hotkeyConfig,
                onChange: { viewModel.updateHotkey($0) }
            )

            // Quit
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

// MARK: - Slot Card

private struct SlotCardView: View {
    let slot: ReservedSlot
    let isExpanded: Bool
    let usedEdges: Set<EdgePosition>
    @ObservedObject var viewModel: ControlPanelViewModel

    private var sizeLabel: String {
        switch slot.reservedArea.size {
        case .pixels(let v): return "\(Int(v))px"
        case .percentage(let v): return "\(Int(v * 100))%"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row — always visible
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.expandedSlotID = isExpanded ? nil : slot.id
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 12)

                    Circle()
                        .fill(slot.isActive ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)

                    Text(slot.reservedArea.edge.rawValue.capitalized)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(sizeLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if let app = slot.boundApp {
                        Text(app.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            // Expanded details
            if isExpanded {
                Divider()
                    .padding(.horizontal, 8)

                VStack(alignment: .leading, spacing: 8) {
                    // Enable toggle
                    Toggle("Enable", isOn: Binding(
                        get: { slot.isActive },
                        set: { _ in viewModel.toggleSlotActive(slot.id) }
                    ))
                    .controlSize(.small)

                    // Position
                    HStack {
                        Text("Position")
                            .font(.caption)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { slot.reservedArea.edge },
                            set: { viewModel.setSlotEdge(slot.id, edge: $0) }
                        )) {
                            ForEach(EdgePosition.allCases, id: \.self) { edge in
                                Text(edge.rawValue.capitalized)
                                    .tag(edge)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }

                    // Size type
                    HStack {
                        Text("Size")
                            .font(.caption)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { viewModel.slotSizeType(slot) },
                            set: { viewModel.setSlotSizeType(slot.id, type: $0) }
                        )) {
                            Text("%").tag("percentage")
                            Text("px").tag("pixels")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 80)
                    }

                    // Size slider
                    let sizeType = viewModel.slotSizeType(slot)
                    let sizeValue = viewModel.slotSizeValue(slot)
                    HStack {
                        Slider(
                            value: Binding(
                                get: { sizeValue },
                                set: { viewModel.setSlotSizeValue(slot.id, value: $0) }
                            ),
                            in: sizeType == "percentage" ? 10...50 : 200...1000,
                            step: sizeType == "percentage" ? 1 : 10
                        )
                        Text(sizeType == "percentage"
                             ? "\(Int(sizeValue))%"
                             : "\(Int(sizeValue))px")
                            .monospacedDigit()
                            .font(.caption)
                            .frame(width: 45, alignment: .trailing)
                    }

                    // Bound app
                    HStack {
                        Text("App")
                            .font(.caption)
                        Spacer()
                        if let app = slot.boundApp {
                            HStack(spacing: 4) {
                                Text(app.displayName)
                                    .font(.caption)
                                    .lineLimit(1)
                                Button {
                                    viewModel.unbindApp(slot.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Button(slot.boundApp == nil ? "Select" : "Change") {
                            viewModel.showAppPickerForSlot(slot.id)
                        }
                        .controlSize(.mini)
                    }

                    // Remove button
                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            viewModel.removeSlot(slot.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                                .font(.caption)
                        }
                        .controlSize(.mini)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}
