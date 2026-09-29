import SwiftUI

/// Teach it words — add, edit, disable, delete. Simplified from Parla's own `DictionaryView.swift`:
/// same two entry types and the same risk warning, without that app's design-token system or search
/// bar, which don't exist here.
struct DictionaryView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss

    @State private var newHear = ""
    @State private var newWrite = ""
    @State private var kind: DictionaryEntry.Kind = .correction

    private var draft: DictionaryEntry {
        DictionaryEntry(kind: kind, hear: newHear, write: newWrite)
    }

    private var canAdd: Bool {
        let hear = newHear.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hear.isEmpty else { return false }
        if kind == .correction {
            return !newWrite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            // A sheet on macOS gets no built-in close control — unlike iOS, there's no swipe-down
            // and no automatic "X". Without this row the only way out was Force Quitting the whole
            // app, which is exactly what happened before this was added.
            HStack {
                Text("Dictionary").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .top], 16)

            composer
            Divider()

            if model.dictionaryEntries.isEmpty {
                Text("No entries yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.dictionaryEntries) { entry in
                        DictionaryRow(
                            entry: entry,
                            onToggle: { model.toggleDictionaryEntry(entry) },
                            onDelete: { model.removeDictionaryEntry(entry) }
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 420, minHeight: 360)
        // Escape is the conventional way to back out of a macOS sheet — the Done button above
        // covers mouse/trackpad, this covers the keyboard.
        .onExitCommand { dismiss() }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $kind) {
                Text("When you hear… write…").tag(DictionaryEntry.Kind.correction)
                Text("Know this word").tag(DictionaryEntry.Kind.vocabulary)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 8) {
                TextField(kind == .correction ? "heard" : "word", text: $newHear)
                    .textFieldStyle(.roundedBorder)

                if kind == .correction {
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    TextField("written", text: $newWrite)
                        .textFieldStyle(.roundedBorder)
                }

                Button("Add") { add() }
                    .disabled(!canAdd)
                    .keyboardShortcut(.return, modifiers: [])
            }

            if canAdd, case .ambiguous(let message) = draft.risk {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(message)
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .padding(16)
    }

    private func add() {
        guard canAdd else { return }
        model.addDictionaryEntry(
            DictionaryEntry(
                kind: kind,
                hear: newHear.trimmingCharacters(in: .whitespacesAndNewlines),
                write: kind == .correction
                    ? newWrite.trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""
            )
        )
        newHear = ""
        newWrite = ""
    }
}

private struct DictionaryRow: View {
    let entry: DictionaryEntry
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { entry.isEnabled }, set: { _ in onToggle() }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)

            VStack(alignment: .leading, spacing: 2) {
                if entry.kind == .correction {
                    HStack(spacing: 4) {
                        Text(entry.hear).foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                        Text(entry.write).fontWeight(.medium)
                    }
                } else {
                    Text(entry.hear).fontWeight(.medium)
                }

                if entry.timesFired > 0 {
                    Text("fired \(entry.timesFired)×")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .opacity(entry.isEnabled ? 1 : 0.4)

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}
