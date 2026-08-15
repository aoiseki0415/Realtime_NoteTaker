import SwiftUI

@main
struct RealtimeNoteTakerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 920, minHeight: 680)
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.activeSession == nil {
                SetupView()
            } else {
                MeetingView()
            }
        }
        .alert("確認が必要です", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("閉じる", role: .cancel) { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
        .confirmationDialog(
            "一時的な全転写を削除しますか？",
            isPresented: Binding(
                get: { model.pendingDeletionSession != nil },
                set: { if !$0 { model.handleTemporaryTranscriptDeletion(delete: false) } }
            ),
            titleVisibility: .visible
        ) {
            Button("削除する", role: .destructive) { model.handleTemporaryTranscriptDeletion(delete: true) }
            Button("保持する") { model.handleTemporaryTranscriptDeletion(delete: false) }
        } message: {
            Text("原音声は保存されません。重要発話ログと構造化したまとめはMarkdownとして保存済みです。")
        }
    }
}

struct SetupView: View {
    @Environment(AppModel.self) private var model
    @State private var isShowingAPIKeySheet = false
    @State private var draft = MeetingConfiguration()

    var body: some View {
        Form {
            Section("会議の設定") {
                TextField("会議名", text: $draft.title)
                Picker("利用場面", selection: $draft.mode) {
                    ForEach(MeetingMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Stepper("自分以外の人数: \(draft.otherParticipantCount)名", value: $draft.otherParticipantCount, in: 0...20)
                Picker("議事録テンプレート", selection: $draft.template) {
                    ForEach(MinutesTemplate.allCases) { Text($0.rawValue).tag($0) }
                }
            }

            Section("音声機器") {
                if draft.mode.requiresMicrophone {
                    Picker("マイク入力", selection: $draft.microphoneDeviceMode) {
                        ForEach(AudioDeviceMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                Picker("スピーカー出力", selection: $draft.speakerDeviceMode) {
                    ForEach(AudioDeviceMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Text("イヤホンを選ぶ場合は、Macのコントロールセンターでも同じイヤホンを入力・出力デバイスとして選択してください。システム音声の取得自体は、スピーカー出力の選択に左右されません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if draft.mode.requiresSystemAudio {
                    Picker(draft.mode == .online ? "オンライン会議アプリ" : "動画を再生するアプリ", selection: $draft.meetingApp) {
                        ForEach(MeetingApp.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Text("Zoom、Microsoft Teams、Google Chromeから、音声を取得するアプリを選択してください。Google MeetはGoogle Chromeを選びます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("保存先") {
                TextField("GitHubリポジトリのローカルパス", text: $draft.repositoryPath)
                Text("議事録は 議事録管理/YYYY/MM/ 以下に保存し、終了時に自動でGitHubへプッシュします。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("OpenAI API") {
                LabeledContent("APIキー") {
                    Text(model.hasOpenAIAPIKey ? "Keychainに登録済み" : "未登録")
                        .foregroundStyle(model.hasOpenAIAPIKey ? .green : .orange)
                }
                Button(model.hasOpenAIAPIKey ? "APIキーを更新" : "APIキーを登録") {
                    isShowingAPIKeySheet = true
                }
                Text("開始前または終了後に、OpenAI Platform の Usage で利用額・クレジット残高を確認してください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("OpenAI Platform の Usage を開く", destination: URL(string: "https://platform.openai.com/usage")!)
            }

            Section("同意確認") {
                Toggle("参加者への録音・文字起こしの通知と同意を確認しました", isOn: $draft.hasConfirmedConsent)
                Text("文字起こしと30秒ごとの議事録整理のため、音声および必要最小限のテキストをOpenAI APIへ送信します。原音声は保存しません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("音声取得を開始") {
                    model.configuration = draft
                    model.startMeeting()
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.hasConfirmedConsent || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("Realtime NoteTaker")
        .onAppear { draft = model.configuration }
        .sheet(isPresented: $isShowingAPIKeySheet) {
            APIKeySheet(isPresented: $isShowingAPIKeySheet)
        }
    }
}

struct APIKeySheet: View {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool
    @State private var apiKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("OpenAI APIキー").font(.title2.bold())
            SecureField("sk-...", text: $apiKey)
            Text("キーはこのMacのKeychainにだけ保存します。GitHub、議事録、アプリのログには保存しません。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("キャンセル") { isPresented = false }
                Button("Keychainに保存") {
                    model.saveOpenAIAPIKey(apiKey)
                    if model.lastError == nil { isPresented = false }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

struct MeetingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        guard let session = model.activeSession else { return AnyView(EmptyView()) }
        return AnyView(VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(session.configuration.title).font(.title2.bold())
                    Text("\(session.configuration.mode.rawValue) ・ \(model.isCapturing ? "音声取得中" : "終了処理中")")
                        .foregroundStyle(model.isCapturing ? .red : .secondary)
                    if let error = model.captureError {
                        Text("音声取得エラー: \(error)")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
                Spacer()
                if model.isCapturing {
                    Button("会議を終了") { model.finishMeeting() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("テストを中止して設定へ戻る") { model.abandonMeeting() }
                }
            }
            .padding()
            Divider()
            HStack(spacing: 0) {
                StructuredMinutesView(session: session)
                Divider()
                ImportantTranscriptView(session: session)
            }
        })
    }
}

struct StructuredMinutesView: View {
    @Environment(AppModel.self) private var model
    let session: MeetingSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("構造化したまとめ").font(.title3.bold())
                ForEach(session.structuredMinutes.template.sections, id: \.self) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section).font(.headline)
                        TextEditor(text: Binding(
                            get: { session.structuredMinutes.sections[section, default: ""] },
                            set: { model.updateSection(section, text: $0) }
                        ))
                        .frame(minHeight: 80)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity)
    }
}

struct ImportantTranscriptView: View {
    let session: MeetingSession

    var body: some View {
        VStack(spacing: 0) {
            Text("受信した発話（確認用）")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.top, .horizontal])
            List(session.temporaryTranscript.sorted(by: { $0.startedAt < $1.startedAt })) { segment in
                TranscriptRow(segment: segment)
            }
            .frame(minHeight: 160)
            Divider()
            Text("重要発話ログ")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            List(session.importantSegments.sorted(by: { $0.startedAt < $1.startedAt })) { segment in
                TranscriptRow(segment: segment)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct TranscriptRow: View {
    let segment: TranscriptSegment
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(segment.speaker) ・ \(segment.startedAt.formatted(date: .omitted, time: .standard))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(segment.text)
        }
        .padding(.vertical, 3)
    }
}
