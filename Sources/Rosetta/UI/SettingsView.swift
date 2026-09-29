import SwiftUI

struct SettingsView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var keyDraft = ""
    @State private var installCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Settings").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            claudeCodeSection
            Divider()
            apiKeySection

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 360)
        .onExitCommand { dismiss() }
    }

    // MARK: - Claude Code

    private var claudeCodeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Claude Code").font(.subheadline).foregroundStyle(.secondary)

            if CLITranslator.binaryPath == nil {
                // Not installed
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    Text("Not installed")
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Prosetta translates via Claude Code — a free CLI that uses your existing Claude account. Install it in 2 steps:")
                            .font(.caption).foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            Label("Paste into Terminal:", systemImage: "1.circle.fill")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Text("npm install -g @anthropic-ai/claude-code")
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.1)))
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString("npm install -g @anthropic-ai/claude-code", forType: .string)
                                    installCopied = true
                                    Task { try? await Task.sleep(for: .seconds(2)); installCopied = false }
                                } label: {
                                    Image(systemName: installCopied ? "checkmark" : "doc.on.doc")
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                .foregroundStyle(installCopied ? .green : .secondary)
                            }

                            Label("Then run `claude` in Terminal and type `/login`.", systemImage: "2.circle.fill")
                                .font(.caption).foregroundStyle(.secondary)
                        }

                        Link("More info at claude.ai/download →", destination: URL(string: "https://claude.ai/download")!)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

            } else if model.cliLoggedIn {
                // Installed and signed in
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Connected — translation is using your Claude account")
                    Spacer()
                    Button("Re-check") { model.recheckCLILogin() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            } else {
                // Installed but not signed in
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    Text("Not signed in")
                    Spacer()
                    Button("Re-check") { model.recheckCLILogin() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Claude Code is installed but you haven't signed in yet. To sign in:")
                            .font(.caption).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Open Terminal", systemImage: "1.circle.fill")
                                .font(.caption).foregroundStyle(.secondary)
                            Label("Type `claude` and press Return", systemImage: "2.circle.fill")
                                .font(.caption).foregroundStyle(.secondary)
                            Label("Type `/login` and follow the browser prompt", systemImage: "3.circle.fill")
                                .font(.caption).foregroundStyle(.secondary)
                            Label("Come back here and tap Re-check", systemImage: "4.circle.fill")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Direct API key fallback

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Anthropic API key").font(.subheadline).foregroundStyle(.secondary)
            Text("Don't have Claude Code? Paste an API key from console.anthropic.com as a fallback. Used only when Claude Code isn't available.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                SecureField("sk-ant-…", text: $keyDraft)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    model.saveAPIKey(keyDraft)
                    keyDraft = ""
                }
                .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if model.apiKeyConfigured {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("API key saved")
                        .font(.caption)
                    Spacer()
                    Button("Remove", role: .destructive) { model.removeAPIKey() }
                        .buttonStyle(.borderless)
                }
            }
        }
    }
}
