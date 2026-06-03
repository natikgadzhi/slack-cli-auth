import AppKit
import SwiftUI

/// A monospaced shell command in a subtle rounded surface with a copy button.
/// Used by the success screen for its install and inspect snippets.
struct CopyableCommand: View {
  private let command: String
  @State private var copied = false

  init(_ command: String) {
    self.command = command
  }

  var body: some View {
    HStack(spacing: 10) {
      Text(command)
        .font(.body.monospaced())
        .textSelection(.enabled)
        // Wrap rather than truncate, so the full command is always readable.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)

      Button(action: copy) {
        // Fixed-size icon so swapping checkmark/doc.on.doc never resizes the row.
        Image(systemName: copied ? "checkmark" : "doc.on.doc")
          .foregroundStyle(copied ? Color.green : .secondary)
          .frame(width: 18, height: 18)
          .contentShape(.rect)
      }
      .buttonStyle(.borderless)
      .help("Copy to clipboard")
      .accessibilityLabel(copied ? "Copied" : "Copy command")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(.quaternary, in: .rect(cornerRadius: 8))
  }

  private func copy() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(command, forType: .string)
    // Instant feedback — no transition. Reverts shortly after.
    copied = true
    Task {
      try? await Task.sleep(for: .seconds(1))
      copied = false
    }
  }
}
