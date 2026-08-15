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

    var body: some View {
        @Bindable var model = model
        Form {
            Section("会議の設定") {
                TextField("会議名", text: $model.configuration.title)
                Picker("利用場面", selection: $model.configuration.mode) {
                    ForEach(MeetingMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Stepper("自分以外の人数: \(model.configuration.otherParticipantCount)名", value: $model.configuration.otherParticipantCount, in: 0...20)
                Picker("議事録テンプレート", selection: $model.configuration.template) {
                    ForEach(MinutesTemplate.allCases) { Text($0.rawValue).tag($0) }
                }
            }

            Section("音声入力") {
                Picker("使用する音声機器", selection: $model.configuration.audioDeviceMode) {
                    ForEach(AudioDeviceMode.allCases) { Text($0.rawValue).tag($0) }
                }
                if model.configuration.mode.requiresMicrophone {
                    TextField("マイクデバイス名（開始時に確認）", text: $model.configuration.microphoneName)
                }
                if model.configuration.mode == .online {
                    Picker("オンライン会議アプリ", selection: $model.configuration.meetingApp) {
                        ForEach(MeetingApp.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                if model.configuration.mode.requiresSystemAudio {
                    TextField("システム音声の対象（開始時に選択）", text: $model.configuration.systemAudioTarget)
                    Text("Google Meetは、実際に使用するブラウザを音声取得対象として選択します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("保存先") {
                TextField("GitHubリポジトリのローカルパス", text: $model.configuration.repositoryPath)
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
            }

            Section("同意確認") {
                Toggle("参加者への録音・文字起こしの通知と同意を確認しました", isOn: $model.configuration.hasConfirmedConsent)
                Text("文字起こしと30秒ごとの議事録整理のため、音声および必要最小限のテキストをOpenAI APIへ送信します。原音声は保存しません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("音声取得を開始") { model.startMeeting() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.configuration.hasConfirmedConsent || model.configuration.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("Realtime NoteTaker")
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
                }
                Spacer()
                if model.isCapturing {
                    Button("確認用の発話を追加") { model.appendDemoSegment() }
                    Button("会議を終了") { model.finishMeeting() }
                        .buttonStyle(.borderedProminent)
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
        List(session.importantSegments.sorted(by: { $0.startedAt < $1.startedAt })) { segment in
            VStack(alignment: .leading, spacing: 4) {
                Text("\(segment.speaker) ・ \(segment.startedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(segment.text)
            }
            .padding(.vertical, 3)
        }
        .overlay(alignment: .topLeading) {
            Text("重要発話ログ")
                .font(.title3.bold())
                .padding()
                .allowsHitTesting(false)
        }
        .padding(.top, 38)
        .frame(maxWidth: .infinity)
    }
}
