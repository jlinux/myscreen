import SwiftUI

struct PermissionGuideView: View {
    let onGranted: () -> Void
    @State private var isChecking = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)

            Text("Accessibility Permission Required")
                .font(.headline)

            Text("MyScreen needs Accessibility permission to manage window positions and sizes.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if isChecking {
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for permission...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(isChecking ? "Open System Settings Again" : "Grant Permission") {
                isChecking = true
                AccessibilityHelper.waitForTrust {
                    onGranted()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(width: 300)
    }
}
