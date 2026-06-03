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
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(command)
        .font(.body.monospaced())
        .textSelection(.enabled)
        // Wrap rather than truncate, so the full command is always readable.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)

      Button(action: copy) {
        Label(copied ? "Copied" : "Copy command", systemImage: copied ? "checkmark" : "doc.on.doc")
          .labelStyle(.iconOnly)
          .contentTransition(.symbolEffect(.replace))
      }
      .buttonStyle(.borderless)
      .help("Copy to clipboard")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(.quaternary, in: .rect(cornerRadius: 8))
  }

  private func copy() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(command, forType: .string)
    copied = true
    Task {
      try? await Task.sleep(for: .seconds(2))
      copied = false
    }
  }
}
