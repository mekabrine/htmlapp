import SwiftUI

/// A focused cold-launch path for the Lock Screen microphone widget. It avoids
/// mounting or warming the Library before capture starts.
struct LockScreenVoiceCreateView: View {
    let cancel: () -> Void
    @EnvironmentObject private var store: AppStore
    @StateObject private var dictation = ForgeDictation()
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
                                 shortcutSource: "libraryMic")
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
            VStack(spacing: 22) {
                TextEditor(text: $prompt)
                    .font(.title3)
                    .scrollContentBackground(.hidden)
                    .padding(14)
                    .frame(maxWidth: 620, maxHeight: .infinity)
                    .background(Color(uiColor: .secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if prompt.isEmpty {
                            Text(dictation.recording ? "Speak your app idea…" : dictation.status)
                                .foregroundStyle(.secondary)
                                .padding(20)
                                .allowsHitTesting(false)
                        }
                    }

                Button {
                    if dictation.recording {
                        dictation.stop()
                    } else if !dictation.transcribingOffline && !dictation.requestingPermission {
                        startupTask?.cancel()
                        startupTask = Task { await dictation.start(tapToStop: true) }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(dictation.recording ? Color.red : Color.accentColor)
                            .frame(width: 154, height: 154)
                            .shadow(color: (dictation.recording ? Color.red : Color.accentColor).opacity(0.3), radius: 24, y: 10)
                        Image(systemName: dictation.recording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 62, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .disabled(dictation.requestingPermission || dictation.transcribingOffline)
                .accessibilityLabel(dictation.recording ? "Stop recording" : "Start recording")

                Text(dictation.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 34)

                if dictation.canRetryTranscription {
                    Button("Retry Transcription") { dictation.retryTranscription() }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
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
                    guard !idea.isEmpty else { return }
                    dictation.cancel()
                    generationPrompt = idea
                    showingGeneration = true
                } label: {
                    Label("Generate", systemImage: "sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || dictation.recording || dictation.transcribingOffline)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.regularMaterial)
            }
            .task {
                startupTask?.cancel()
                startupTask = Task { await dictation.startFromLockScreen() }
                await startupTask?.value
            }
            .onChange(of: dictation.transcript) { words in
                prompt = words
            }
            .alert("Pause other audio", isPresented: $dictation.blockedByOtherAudio) {
                Button("OK", role: .cancel) { dictation.dismissAudioWarning() }
            } message: {
                Text("Pause music or another recording app, then tap the microphone again.")
            }
        }
    }
}
