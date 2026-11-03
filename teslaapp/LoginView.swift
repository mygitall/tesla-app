import SwiftUI

struct LoginView: View {
    @ObservedObject var api: TeslaAPI

    enum Mode: String, CaseIterable { case key = "密钥", password = "密码" }

    @State private var mode: Mode = .key
    @State private var input = ""
    @State private var errorText: String?
    @State private var working = false
    @State private var editServer = false
    @State private var serverText = ""
    @FocusState private var focused: Bool

    /// 兜底：只要 App 里带着内置密钥，就自动完成登录，用户永远看不到这个页面
    private func autoLoginIfPossible() {
        guard !AppConfig.accessKey.isEmpty, !working else {
            focused = true
            return
        }
        working = true
        Task {
            defer { Task { @MainActor in working = false } }
            do {
                try await api.keyLogin(AppConfig.accessKey)
            } catch {
                await MainActor.run {
                    focused = true
                    errorText = "自动登录失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private var canSubmit: Bool { !input.isEmpty && !working }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 10) {
                    Image(systemName: "bolt.fill")
                        .font(.app(34))
                        .foregroundStyle(Theme.amber, Theme.green)
                    Text("TESLA DASH")
                        .font(.system(size: 17 * TypoScale.factor(17), weight: .bold, design: .rounded))
                        .tracking(3)
                        .foregroundColor(Theme.text)
                }
                .padding(.bottom, 26)

                Picker("", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 18)
                .onChange(of: mode) { _ in
                    input = ""
                    errorText = nil
                    focused = true
                }

                VStack(spacing: 14) {
                    Group {
                        if mode == .key {
                            TextField("粘贴密钥或免密链接", text: $input)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .keyboardType(.URL)
                        } else {
                            SecureField("访问密码", text: $input)
                                .textContentType(.password)
                        }
                    }
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit { submit() }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1)
                    )
                    .foregroundColor(Theme.text)
                    .font(.system(size: (mode == .key ? 13 : 16) * TypoScale.factor(14), design: mode == .key ? .monospaced : .default))

                    if let errorText {
                        Text(errorText)
                            .font(.app(12))
                            .foregroundColor(Theme.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: submit) {
                        HStack(spacing: 8) {
                            if working { ProgressView().tint(.black) }
                            Text(working ? "验证中…" : "进入")
                                .font(.app(15, .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.green))
                        .foregroundColor(Color(red: 0.043, green: 0.09, blue: 0.05))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.5)
                }
                .frame(maxWidth: 340)

                Text(mode == .key
                     ? "密钥链接在服务器上：/opt/tesla-dash/data/.access-key"
                     : "密码是服务器 .env 里的 APP_PASSWORD")
                    .font(.app(10))
                    .foregroundColor(Theme.dim)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)

                Spacer()

                Button {
                    Haptics.tap()
                    serverText = api.baseURLString
                    editServer = true
                } label: {
                    HStack(spacing: 5) {
                        Text("服务器：\(api.baseURLString)")
                            .font(.appMono(10))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "pencil")
                            .font(.app(9))
                    }
                    .foregroundColor(Theme.dim)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 10)

                Spacer()
            }
            .padding(.horizontal, 26)
        }
        .onAppear {
            autoLoginIfPossible()
        }
        .sheet(isPresented: $editServer) {
            ServerEditSheet(api: api, text: $serverText)
        }
    }

    private func submit() {
        guard canSubmit else { return }
        working = true
        errorText = nil
        let value = input

        Task {
            do {
                if mode == .key {
                    _ = try await api.keyLogin(value)
                } else {
                    try await api.login(password: value)
                }
            } catch {
                errorText = error.localizedDescription
            }
            working = false
        }
    }
}


/// 登录页修改服务器地址（未登录时也能改，避免"连错服务器就登不进去"）
struct ServerEditSheet: View {
    @ObservedObject var api: TeslaAPI
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("https://www.zhangweiwei.cc", text: $text)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(.appMono(14))
                } header: {
                    Text("服务器地址")
                } footer: {
                    Text("换成你自己的服务器地址；保存后需要重新登录。")
                        .font(.app(11))
                }
                Section {
                    Button("恢复默认") {
                        text = "https://www.zhangweiwei.cc"
                    }
                }
            }
            .navigationTitle("修改服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty { api.baseURLString = t }
                        Haptics.success()
                        dismiss()
                    }
                }
            }
        }
    }
}
