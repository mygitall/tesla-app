import SwiftUI

struct SettingsSheet: View {
    @ObservedObject var api: TeslaAPI
    @Environment(\.dismiss) private var dismiss

    @State private var server = ""
    @State private var saved = false
    @State private var priceText = ""
    @State private var priceSaved = false
    @State private var cleared = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("https://www.zhangweiwei.cc", text: $server)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(.appMono(14))
                } header: {
                    Text("服务器地址")
                } footer: {
                    Text("修改后需要重新登录。")
                        .font(.app(11))
                }

                Section {
                    HStack {
                        Text("电价")
                        Spacer()
                        TextField("1.60", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.appMono(14))
                            .frame(width: 80)
                        Text("元/度").foregroundColor(.secondary)
                    }
                    Button(priceSaved ? "已保存" : "保存电价") {
                        if let v = Double(priceText.replacingOccurrences(of: ",", with: ".")), v > 0 {
                            Task {
                                await api.setElectricityPrice(v)
                                priceSaved = true
                            }
                        }
                    }
                    .disabled(Double(priceText.replacingOccurrences(of: ",", with: ".")) == nil)
                } header: {
                    Text("用电成本")
                } footer: {
                    Text("用于计算充电花费。不同地区/峰谷电价不同，按你的电费单填写。")
                        .font(.app(11))
                }

                Section {
                    Button("清除本地缓存") {
                        api.clearAllCaches()
                        cleared = true
                    }
                    if cleared {
                        Text("已清除").font(.system(size: 12)).foregroundColor(.secondary)
                    }
                } header: {
                    Text("存储")
                } footer: {
                    Text("清除离线数据、诊断日志与登录会话，不影响服务器数据。")
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
                    NavigationLink {
                        CrashLogView()
                    } label: {
                        HStack {
                            Text("诊断日志")
                            Spacer()
                            Text(CrashLogger.read().isEmpty ? "无记录" : "有记录")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    NavigationLink {
                        ActionHistoryView(api: api)
                    } label: {
                        HStack {
                            Text("操作历史")
                            Spacer()
                            Text("锁车 / 空调 / 启动")
                                .font(.app(12))
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("记录")
                } footer: {
                    Text("最近 1000 条控制操作，含自动上锁。")
                        .font(.app(11))
                }

                Section {
                    HStack {
                        Text("版本"); Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("接口"); Spacer()
                        Text("/api/app/summary").foregroundColor(.secondary).font(.appMono(12))
                    }
                } footer: {
                    Text("离车自动上锁、远程控制均由服务器执行，App 只负责展示与下发。")
                        .font(.app(11))
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
            .onAppear {
                server = api.baseURLString
                priceText = api.electricityPrice.map { String(format: "%.2f", $0) } ?? "1.60"
            }
        }
        .preferredColorScheme(.dark)
    }
}


// MARK: - 操作历史

struct ActionHistoryView: View {
    @ObservedObject var api: TeslaAPI

    private var grouped: [(String, [ActionRecord])] {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        var order: [String] = []
        var map: [String: [ActionRecord]] = [:]
        for a in api.actions {
            let d = Date(timeIntervalSince1970: TimeInterval(a.ts))
            let key = f.string(from: d)
            if map[key] == nil { map[key] = []; order.append(key) }
            map[key]?.append(a)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        List {
            if let e = api.actionsError {
                Text(e).font(.app(13)).foregroundColor(.red)
            }
            ForEach(grouped, id: \.0) { day, items in
                Section(header: Text(dayLabel(day))) {
                    ForEach(items) { a in
                        row(a)
                    }
                }
            }
            if api.actionsHasMore {
                Button {
                    Task { await api.loadActions(append: true) }
                } label: {
                    HStack {
                        Spacer()
                        if api.actionsLoading { ProgressView().scaleEffect(0.7) }
                        Text("加载更多").foregroundColor(.accentColor)
                        Spacer()
                    }
                }
            }
            if api.actions.isEmpty && !api.actionsLoading {
                Text("还没有操作记录").font(.app(13)).foregroundColor(.secondary)
            }
        }
        .navigationTitle("操作历史")
        .refreshable { await api.loadActions() }
        .task { if api.actions.isEmpty { await api.loadActions() } }
    }

    private func row(_ a: ActionRecord) -> some View {
        HStack(spacing: 10) {
            Image(systemName: a.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .font(.app(14))
                .foregroundColor(a.ok ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(a.label ?? a.action).font(.app(14))
                    if a.source == "auto" {
                        Text("自动")
                            .font(.app(9))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                            .foregroundColor(.orange)
                    }
                }
                if let d = a.detail, !d.isEmpty {
                    Text(d).font(.app(11)).foregroundColor(.secondary).lineLimit(2)
                }
            }
            Spacer()
            Text(timeLabel(a.ts)).font(.appMono(12)).foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func timeLabel(_ ts: Int) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    private func dayLabel(_ key: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: key) else { return key }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "今天" }
        if cal.isDateInYesterday(d) { return "昨天" }
        let g = DateFormatter(); g.dateFormat = "M月d日"
        return g.string(from: d)
    }
}


// MARK: - 诊断日志（崩溃记录）

struct CrashLogView: View {
    @State private var text = ""
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if text.isEmpty {
                    Text("没有异常记录").font(.system(size: 13)).foregroundColor(.secondary)
                } else {
                    Text(text)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
        .navigationTitle("诊断日志")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button(copied ? "已复制" : "复制") {
                        UIPasteboard.general.string = text
                        copied = true
                    }
                    Button("清空", role: .destructive) {
                        CrashLogger.clear()
                        text = ""
                    }
                }
            }
        }
        .onAppear { text = CrashLogger.read() }
    }
}
