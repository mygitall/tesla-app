import SwiftUI

struct SettingsSheet: View {
    @ObservedObject var api: TeslaAPI
    @Environment(\.dismiss) private var dismiss

    @State private var server = ""
    @State private var saved = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("https://www.zhangweiwei.cc", text: $server)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(.system(size: 14, design: .monospaced))
                } header: {
                    Text("服务器地址")
                } footer: {
                    Text("修改后需要重新登录。")
                        .font(.system(size: 11))
                }

                Section {
                    Button("恢复默认") {
                        server = "https://www.zhangweiwei.cc"
                    }
                    Button(role: .destructive) {
                        api.logout()
                        dismiss()
                    } label: {
                        Text("退出登录")
                    }
                }

                Section {
                    HStack {
                        Text("版本"); Spacer(); Text("1.0").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("接口"); Spacer()
                        Text("/api/app/summary").foregroundColor(.secondary).font(.system(size: 12, design: .monospaced))
                    }
                } footer: {
                    Text("离车自动上锁、远程控制均由服务器执行，App 只负责展示与下发。")
                        .font(.system(size: 11))
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let t = server.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty { api.baseURLString = t }
                        api.logout()
                        dismiss()
                    }
                }
            }
            .onAppear { server = api.baseURLString }
        }
        .preferredColorScheme(.dark)
    }
}
