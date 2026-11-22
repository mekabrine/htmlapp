import SwiftUI

/// A focused cold-launch path for the Lock Screen microphone widget. It avoids
/// mounting or warming the Library before capture starts.
@MainActor
struct LockScreenVoiceCreateView: View {
    let cancel: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: AppStore
    @StateObject private var dictation = ForgeDictation()
    @StateObject private var context = ForgeAttachmentSelection()
    @State private var needsMicTest = ForgeDictation.usesAlternative
    @State private var testResult: Bool?
    @State private var generationContext: [ForgeAttachment] = []
    @State private var prompt = ""
    @State private var generationPrompt: String?
    @State private var showingGeneration = false
    @State private var startupTask: Task<Void, Never>?

    var body: some View {
        capture
        .fullScreenCover(isPresented: $showingGeneration, onDismiss: cancel) {
            if let generationPrompt {
                AIGenerationView(initialPrompt: generationPrompt,
                                 shortcutGenerationNonce: 1,
                                 shortcutSource: "libraryMic", initialAttachments: generationContext)
                    .environmentObject(store)
                    .interactiveDismissDisabled(true)
            }
        }
        .onDisappear {
            startupTask?.cancel()
            dictation.cancel()
        }
    }

    private var capture: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TextEditor(text: $prompt)
                        .font(.title3)
                        .scrollContentBackground(.hidden)
                        .padding(14)
                        .frame(minHeight: 116)
                        .background(Color(uiColor: .secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            if prompt.isEmpty {
                                Text(needsMicTest ? "Type an idea, or say a few words to test the microphone." : "Describe your app…")
                                    .foregroundStyle(.secondary)
                                    .padding(20)
                                    .allowsHitTesting(false)
                            }
                        }

                    ForgeAdditionalContext(selection: context)
                    ForEach(context.files) { file in
                        HStack {
                            Label(file.name, systemImage: "paperclip").lineLimit(1)
                            Spacer()
                            Button {
                                context.items.removeAll { $0.id == file.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .accessibilityLabel("Remove \(file.name)")
                        }
                        .font(.subheadline)
                    }

                    Button {
                        if needsMicTest && dictation.recording {
                            dictation.testMicOnRelease()
                        } else if dictation.recording {
                            dictation.release()
                        } else {
                            startCapture(test: needsMicTest)
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: !needsMicTest && dictation.recording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 38, weight: .semibold))
                            if needsMicTest { Text("Testing").font(.caption.weight(.semibold)) }
                        }
                        .foregroundStyle(.white)
                        .frame(width: 106, height: 106)
                        .background(micColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(dictation.requestingPermission || dictation.testingMic || dictation.transcribingOffline || dictation.finishingAppleSpeech)
                    .accessibilityLabel(needsMicTest
                        ? (dictation.recording ? "Testing. Tap to check your recording." : "Start microphone test")
                        : (dictation.recording ? "Stop recording" : "Start recording"))

                    if let testResult {
                        Label(testResult ? "Mic test passed" : "Mic test failed",
                              systemImage: testResult ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(testResult ? Color.green : Color.orange)
                    }
                    Text(micStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(minHeight: 34)

                    if dictation.canRetryTranscription {
                        Button("Retry Transcription") { dictation.retryTranscription() }
                    }
                }
                .padding(20)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Describe Your App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dictation.cancel()
                        cancel()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    let idea = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !showingGeneration, !idea.isEmpty else { return }
                    startupTask?.cancel()
                    dictation.cancel()
                    generationContext = context.items
                    generationPrompt = idea
                    showingGeneration = true
                } label: {
                    ForgeGenerationButtonLabel(title: "Generate", systemImage: "sparkles", isLoading: showingGeneration)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(showingGeneration || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (dictation.recording && !needsMicTest) || dictation.transcribingOffline || dictation.testingMic || dictation.finishingAppleSpeech)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.regularMaterial)
            }
            .task { startCapture(test: needsMicTest) }
            .onChange(of: scenePhase) { phase in
                guard phase == .background else { return }
                startupTask?.cancel()
                dictation.cancel()
            }
            .onChange(of: dictation.micTestSucceeded) { succeeded in
                guard needsMicTest, let succeeded, !showingGeneration else { return }
                testResult = succeeded
                needsMicTest = false
                dictation.micTestSucceeded = nil
                startCapture(test: false)
            }
            .onChange(of: dictation.transcript) { words in
                if !words.isEmpty { prompt = words }
            }
            .alert("Additional context", isPresented: Binding(
                get: { context.error != nil }, set: { if !$0 { context.error = nil } }
            )) {
                Button("OK") { context.error = nil }
            } message: { Text(context.error ?? "") }
            .alert("Pause other audio", isPresented: $dictation.blockedByOtherAudio) {
                Button("OK", role: .cancel) { dictation.dismissAudioWarning() }
            } message: {
                Text("Pause music or another recording app, then tap the microphone again.")
            }
        }
    }

    private var micColor: Color {
        if needsMicTest { return .purple }
        return dictation.recording ? .red : .accentColor
    }

    private var micStatus: String {
        if needsMicTest && dictation.recording { return "Say a few words, then tap to test. Your app recording starts next." }
        return dictation.status
    }

    private func startCapture(test: Bool) {
        startupTask?.cancel()
        startupTask = Task { await dictation.start(tapToStop: true, testCapture: test) }
    }
}
