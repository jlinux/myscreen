import SwiftUI

struct ResolutionPickerView: View {
    let groups: [DisplayModeGroup]
    let currentMode: DisplayMode?
    let onSelect: (DisplayMode) -> Void

    /// Best mode per logical resolution: prefer HiDPI, then highest refresh rate.
    private var bestModes: [DisplayMode] {
        groups.map { group in
            // Pick the best mode: HiDPI first, then highest refresh rate
            group.modes.first ?? group.modes[0]
        }
    }

    var body: some View {
        List {
            ForEach(bestModes) { mode in
                ResolutionRowView(
                    mode: mode,
                    isCurrent: isCurrentMode(mode)
                )
                .contentShape(Rectangle())
                .onTapGesture { onSelect(mode) }
                .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
            }
        }
        .listStyle(.plain)
        .frame(height: 180)
    }

    private func isCurrentMode(_ mode: DisplayMode) -> Bool {
        guard let current = currentMode else { return false }
        return current.width == mode.width
            && current.height == mode.height
            && current.isHiDPI == mode.isHiDPI
    }
}

// MARK: - Row

private struct ResolutionRowView: View {
    let mode: DisplayMode
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.caption2)
                .foregroundColor(.accentColor)
                .opacity(isCurrent ? 1 : 0)
                .frame(width: 12)

            Text("\(mode.width) x \(mode.height)")
                .font(.system(.caption, design: .monospaced))

            if mode.isHiDPI {
                HiDPIBadge()
            }

            if mode.isNative {
                NativeBadge()
            }

            Spacer()

            if mode.refreshRate > 0 {
                Text("\(Int(mode.refreshRate))Hz")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isCurrent ? Color.accentColor.opacity(0.1) : Color.clear)
        )
    }
}

// MARK: - Badges

private struct HiDPIBadge: View {
    var body: some View {
        Text("HiDPI")
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.blue))
    }
}

private struct NativeBadge: View {
    var body: some View {
        Text("Native")
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.orange))
    }
}
