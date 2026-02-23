import SwiftUI

/// A view that records a keyboard shortcut from the user (F-011).
struct HotkeyRecorderView: View {
    @Binding var hotkeyConfig: HotkeyConfig
    let onChange: (HotkeyConfig) -> Void
    @State private var isRecording = false

    var body: some View {
        HStack {
            Text("Hotkey")
                .font(.subheadline)
            Spacer()

            if isRecording {
                Text("Press shortcut...")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.accentColor, lineWidth: 1)
                    )

                Button("Cancel") {
                    isRecording = false
                }
                .controlSize(.small)
            } else {
                Text(hotkeyConfig.displayString)
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.1))
                    )

                Button("Change") {
                    isRecording = true
                }
                .controlSize(.small)
            }
        }
        .background(
            isRecording ? KeyRecorderRepresentable(
                onKeyRecorded: { keyCode, modifiers in
                    let config = HotkeyConfig(keyCode: keyCode, modifiers: modifiers)
                    hotkeyConfig = config
                    isRecording = false
                    onChange(config)
                }
            ).frame(width: 0, height: 0) : nil
        )
    }
}

/// NSView that captures key events for hotkey recording.
struct KeyRecorderRepresentable: NSViewRepresentable {
    let onKeyRecorded: (UInt16, UInt64) -> Void

    func makeNSView(context: Context) -> KeyRecorderNSView {
        let view = KeyRecorderNSView()
        view.onKeyRecorded = onKeyRecorded
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyRecorderNSView, context: Context) {
        nsView.onKeyRecorded = onKeyRecorded
    }
}

final class KeyRecorderNSView: NSView {
    var onKeyRecorded: ((UInt16, UInt64) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let keyCode = event.keyCode
        let modifierMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let activeModifiers = event.modifierFlags.intersection(modifierMask)

        guard !activeModifiers.isEmpty else { return }

        var cgFlags: UInt64 = 0
        if activeModifiers.contains(.command) { cgFlags |= CGEventFlags.maskCommand.rawValue }
        if activeModifiers.contains(.option) { cgFlags |= CGEventFlags.maskAlternate.rawValue }
        if activeModifiers.contains(.control) { cgFlags |= CGEventFlags.maskControl.rawValue }
        if activeModifiers.contains(.shift) { cgFlags |= CGEventFlags.maskShift.rawValue }

        onKeyRecorded?(keyCode, cgFlags)
    }
}
