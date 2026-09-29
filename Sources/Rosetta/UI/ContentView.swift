import SwiftUI
import AppKit

struct ContentView: View {
    let model: AppModel

    @State private var showDictionary = false
    @State private var showSettings = false
    @State private var transcriptDraft: String = ""
    @FocusState private var transcriptFocused: Bool
    @State private var pulseLevel: Float = 0
    private let pulseTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            header
            recordButton
            transcriptSection
            pendingCorrectionsSection
            translationSection
            footer
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 560)
        .task {
            await model.start()
        }
        .task(id: model.transcript) {
            transcriptDraft = model.transcript
        }
        .onChange(of: transcriptFocused) { wasFocused, isFocused in
            if wasFocused, !isFocused {
                model.editTranscript(to: transcriptDraft)
            }
        }
        .onReceive(pulseTimer) { _ in
            pulseLevel = model.recordState == .recording ? model.currentLevel : 0
        }
        .sheet(isPresented: $showDictionary) {
            DictionaryView(model: model)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(model: model)
        }
        .alert("Microphone access needed", isPresented: .constant(model.permissionDenied)) {
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Prosetta needs Microphone access to record. Enable it in System Settings → Privacy & Security → Microphone.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Prosetta").font(.headline)
                Spacer()
                Button {
                    showDictionary = true
                } label: {
                    Label("Dictionary", systemImage: "book")
                }
                .buttonStyle(.borderless)

                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.borderless)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Speaking").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: sourceBinding) {
                        ForEach(model.availableSourceLanguages) { language in
                            Text(language.label).tag(language.id)
                        }
                    }
                    .labelsHidden()
                    Button {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Dictation")!)
                    } label: {
                        Text("Add languages in System Settings →")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .padding(.top, 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Translate into").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: targetBinding) {
                        ForEach(Settings.targetLanguageGroups, id: \.title) { group in
                            Section(group.title) {
                                ForEach(group.languages, id: \.self) { lang in
                                    Text(lang).tag(lang)
                                }
                            }
                        }
                    }
                    .labelsHidden()
                }

                Spacer()
            }
        }
    }

    private var sourceBinding: Binding<String> {
        Binding(get: { model.sourceLanguageID }, set: { model.setSourceLanguage($0) })
    }

    private var targetBinding: Binding<String> {
        Binding(get: { model.targetLanguage }, set: { model.setTargetLanguage($0) })
    }

    // MARK: - Record button

    private var recordButton: some View {
        VStack(spacing: 8) {
            Button(action: model.toggleRecording) {
                ZStack {
                    Circle()
                        .fill(recordButtonColor)
                        .frame(width: 84, height: 84)
                        .scaleEffect(1 + CGFloat(pulseLevel) * 0.25)
                        .animation(.easeOut(duration: 0.08), value: pulseLevel)

                    Image(systemName: recordButtonIcon)
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canRecord)

            Text(statusLine).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var canRecord: Bool {
        switch model.recordState {
        case .idle, .done, .failed, .recording: true
        case .transcribing, .translating: false
        }
    }

    private var recordButtonIcon: String {
        model.recordState == .recording ? "stop.fill" : "mic.fill"
    }

    private var recordButtonColor: Color {
        switch model.recordState {
        case .recording: .red
        case .transcribing, .translating: .gray
        default: .accentColor
        }
    }

    private var statusLine: String {
        switch model.recordState {
        case .idle: return "Tap to record"
        case .recording: return "Recording — tap to stop"
        case .transcribing: return "Transcribing…"
        case .translating(let elapsed):
            let dots = String(repeating: "●", count: (elapsed % 3) + 1)
            return "Translating \(dots)"
        case .done: return "Done — tap to record again"
        case .failed(let message): return message
        }
    }

    // MARK: - Transcript

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Transcript").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.transcript, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(model.transcript.isEmpty)
            }
            TextEditor(text: $transcriptDraft)
                .font(.body)
                .frame(minHeight: 80)
                .focused($transcriptFocused)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
        }
    }

    private var pendingCorrectionsSection: some View {
        Group {
            if !model.pendingCorrections.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.pendingCorrections, id: \.self) { pair in
                        HStack {
                            Text("Remember \"\(pair.heard)\" → \"\(pair.meant)\"?")
                                .font(.caption)
                            Spacer()
                            Button("Save") { model.acceptCorrection(pair) }
                                .buttonStyle(.borderless)
                            Button("No") { model.dismissCorrection(pair) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(.yellow.opacity(0.12)))
            }
        }
    }

    // MARK: - Translation

    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Translation").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(model.translatorStatus).font(.caption2).foregroundStyle(.tertiary)
            }
            ScrollView {
                Text(translationDisplayText)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(minHeight: 100)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
        }
    }

    private var translationDisplayText: String {
        if case .translating = model.recordState {
            return model.translation.isEmpty ? "Translating…" : model.translation
        }
        return model.translation
    }

    // MARK: - Footer

    private var isProcessing: Bool {
        switch model.recordState {
        case .transcribing, .translating: return true
        default: return false
        }
    }

    private var footer: some View {
        HStack {
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(model.translation, forType: .string)
            } label: {
                Label("Copy translation", systemImage: "doc.on.doc")
            }
            .disabled(model.translation.isEmpty)

            Button {
                model.editTranscript(to: transcriptDraft)
                model.retranslate()
            } label: {
                Label("Re-translate", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(transcriptDraft.isEmpty || !model.hasTranslator || isProcessing)

            Spacer()

            Text("via Claude — leaves this Mac")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
