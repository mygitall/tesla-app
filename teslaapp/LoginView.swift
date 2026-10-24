import SwiftUI

struct LoginView: View {
    @ObservedObject var api: TeslaAPI

    enum Mode: String, CaseIterable { case key = "密钥", password = "密码" }

    @State private var mode: Mode = .key
    @State private var input = ""
    @State private var errorText: String?
    @State private var working = false
    @FocusState private var focused: Bool

    private var canSubmit: Bool { !input.isEmpty && !working }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 10) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Theme.amber, Theme.green)
                    Text("TESLA DASH")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
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
                    .font(.system(size: mode == .key ? 13 : 16, design: mode == .key ? .monospaced : .default))

                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: submit) {
                        HStack(spacing: 8) {
                            if working { ProgressView().tint(.black) }
                            Text(working ? "验证中…" : "进入")
                                .font(.system(size: 15, weight: .semibold))
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
                    .font(.system(size: 10))
                    .foregroundColor(Theme.dim)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)

                Spacer()

                Text("服务器：\(api.baseURLString)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.dim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.bottom, 10)

                Spacer()
            }
            .padding(.horizontal, 26)
        }
        .onAppear { focused = true }
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
