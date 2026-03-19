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
                        isBindingMissing: viewModel.bindingMissing(for: slot.id),
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
                initialBundleIdentifier: viewModel.preferredBundleIdentifierForPicker,
                onSelect: { viewModel.bindApp($0) },
                onCancel: { viewModel.cancelAppPicker() }
            )
        }
    }
}

// MARK: - Slot Card

private struct SlotCardView: View {
    private enum BindingStatus {
        case disabled
        case unbound
        case missing
        case bound
    }

    let slot: ReservedSlot
    let isExpanded: Bool
    let isBindingMissing: Bool
    let usedEdges: Set<EdgePosition>
    @ObservedObject var viewModel: ControlPanelViewModel

    private var sizeLabel: String {
        switch slot.reservedArea.size {
        case .pixels(let v): return "\(Int(v))px"
        case .percentage(let v): return "\(Int(v * 100))%"
        }
    }

    private var bindingStatus: BindingStatus {
        if !slot.isActive { return .disabled }
        if slot.boundApp == nil { return .unbound }
        if isBindingMissing { return .missing }
        return .bound
    }

    private var statusTitle: String {
        switch bindingStatus {
        case .disabled: return "Disabled"
        case .unbound: return "Unbound"
        case .missing: return "Needs Rebind"
        case .bound: return "Bound"
        }
    }

    private var statusIcon: String {
        switch bindingStatus {
        case .disabled: return "pause.circle.fill"
        case .unbound: return "circle.dashed"
        case .missing: return "exclamationmark.triangle.fill"
        case .bound: return "checkmark.circle.fill"
        }
    }

    private var statusTint: Color {
        switch bindingStatus {
        case .disabled: return .secondary
        case .unbound: return .secondary
        case .missing: return .orange
        case .bound: return .green
        }
    }

    private var statusDescription: String {
        switch bindingStatus {
        case .disabled:
            return "This reserved area is turned off. Turn it back on to apply the layout and binding."
        case .unbound:
            return "No window is linked yet. Pick a target window if this area should auto-move or hide something."
        case .missing:
            return "The previously linked window is not currently available. Rebind it or reopen that window."
        case .bound:
            return "This reserved area is actively tracking the selected window and will manage it automatically."
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        Label(statusTitle, systemImage: statusIcon)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(statusTint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(statusTint.opacity(0.12))
            )
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

                    statusBadge

                    Spacer()

                    if let app = slot.boundApp {
                        Text(app.displayLabel)
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
                                    .disabled(usedEdges.contains(edge) && edge != slot.reservedArea.edge)
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
                                Text(app.displayLabel)
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
                            viewModel.showAppPickerForSlot(
                                slot.id,
                                preferredBundleIdentifier: slot.boundApp?.bundleIdentifier
                            )
                        }
                        .controlSize(.mini)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center, spacing: 8) {
                            Text("Status")
                                .font(.caption)
                            Spacer()
                            statusBadge
                        }

                        Text(statusDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if bindingStatus == .missing {
                            HStack(alignment: .center, spacing: 8) {
                                Label("Bound window not found.", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                Spacer()
                                Button("Rebind") {
                                    viewModel.showAppPickerForSlot(slot.id, preferredBundleIdentifier: slot.boundApp?.bundleIdentifier)
                                }
                                .controlSize(.mini)
                            }
                        } else if bindingStatus == .unbound {
                            Text("Tip: binding a window lets MyScreen restore placement and keep the area aligned to that window.")
                                .font(.caption2)
                                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        }
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
