import SwiftUI

/// 问一问：自然语言查询自己的用车数据（服务端规则引擎，无需联网模型）
struct AskView: View {
    @ObservedObject var api: TeslaAPI
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var asking = false
    @State private var history: [Bubble] = []

    struct Bubble: Identifiable {
        let id = UUID()
        let mine: Bool
        let text: String
        var tag: String? = nil       // "AI" 标记
    }

    private let suggestions = [
        "上个月总里程", "今日充电数据", "本月充电多少次",
        "今天电耗多少", "上次充电", "这个月花了多少电费",
        "我该多久充一次电", "冬天续航掉得厉害正常吗",
    ]

    /// 能问什么（分组示例，点一下直接问）
    private let helpGroups: [(String, [String])] = [
        ("里程", ["今天开了多少公里", "本周里程", "上个月总里程", "今年一共开了多少"]),
        ("充电", ["今日充电数据", "本月充电多少次", "上次充电", "本月充了多少度电"]),
        ("能耗与花费", ["今天电耗多少", "本月百公里电耗", "这个月花了多少电费", "上月电费"]),
        ("建议类（会结合你的数据）", ["我该多久充一次电", "该充到 90% 还是 100%", "冬天续航掉得厉害正常吗"]),
    ]

    @State private var showHelp = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 10) {
                            if history.isEmpty { emptyState }
                            ForEach(history) { b in bubble(b).id(b.id) }
                            if asking {
                                HStack(spacing: 6) {
                                    ProgressView().scaleEffect(0.7)
                                    Text("查询中…").font(.app(12)).foregroundColor(L.dim)
                                }
                                .padding(.vertical, 6)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: history.count) { _ in
                        if let last = history.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }

                inputBar
            }
            .background(L.bg.ignoresSafeArea())
            .navigationTitle("问一问")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("可以直接问我").font(.app(12)).foregroundColor(L.dim)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showHelp.toggle() }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "questionmark.circle").font(.app(10))
                        Text("能问什么？").font(.app(11))
                    }
                    .foregroundColor(L.sand)
                }
                .buttonStyle(.plain)
            }

            FlowChips(items: suggestions) { s in ask(s) }

            if showHelp {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(helpGroups, id: \.0) { group, items in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group).font(.app(11, .medium)).foregroundColor(L.sub)
                            FlowChips(items: items) { s in ask(s) }
                        }
                    }
                    Text("范围说明：只回答与你这辆车数据相关的问题；天气、新闻、闲聊会礼貌拒绝（省钱也防止瞎编）。")
                        .font(.app(10))
                        .foregroundColor(L.dim)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(L.card.opacity(0.6)))
            } else {
                Text("例如「上个月总里程」「今日充电数据」")
                    .font(.app(11)).foregroundColor(L.dim)
            }
        }
    }

    private func bubble(_ b: Bubble) -> some View {
        HStack {
            if b.mine { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                if let tag = b.tag {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles").font(.app(8))
                        Text(tag).font(.app(9))
                    }
                    .foregroundColor(L.sand)
                }
                Text(b.text)
                    .font(.app(13))
                    .foregroundColor(b.mine ? L.bg : L.text)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(b.mine ? L.sand : L.card)
            )
            if !b.mine { Spacer(minLength: 40) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("问点关于车的事…", text: $input)
                .font(.app(13))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(L.card))
                .submitLabel(.send)
                .onSubmit { ask(input) }

            Button {
                ask(input)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.app(26))
                    .foregroundColor(input.isEmpty ? L.dim : L.sand)
            }
            .buttonStyle(.plain)
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || asking)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(L.bg)
    }

    private func ask(_ q: String) {
        let question = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !asking else { return }
        // 输入太短（比如一个字母）：本地提示，不浪费一次网络/模型调用
        if question.count < 2 {
            Haptics.error()
            history.append(Bubble(mine: true, text: question))
            history.append(Bubble(mine: false, text: "问完整一点，比如「本月总里程」「今日充电数据」。点右上「能问什么？」能看到全部可问范围。"))
            input = ""
            return
        }
        Haptics.tap()
        history.append(Bubble(mine: true, text: question))
        input = ""
        asking = true
        Task {
            do {
                let r: AskResp = try await api.ask(question)
                await MainActor.run {
                    asking = false
                    history.append(Bubble(mine: false,
                                          text: r.answer ?? "暂时答不上来",
                                          tag: r.source == "ai" ? "AI 推理" : nil))
                }
            } catch {
                await MainActor.run {
                    asking = false
                    history.append(Bubble(mine: false, text: "查询失败：\(error.localizedDescription)"))
                }
            }
        }
    }
}

/// 自动换行的标签组
struct FlowChips: View {
    let items: [String]
    var onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { s in
                        Button { onTap(s) } label: {
                            Text(s)
                                .font(.app(12))
                                .foregroundColor(L.text)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(L.card))
                                .overlay(Capsule().stroke(L.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var rows: [[String]] {
        var out: [[String]] = []
        var cur: [String] = []
        var w: CGFloat = 0
        for s in items {
            let est = CGFloat(s.count) * 12 + 26
            if w + est > 340 && !cur.isEmpty { out.append(cur); cur = []; w = 0 }
            cur.append(s); w += est + 8
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
}
