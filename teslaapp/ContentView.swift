import SwiftUI

struct ContentView: View {
    @StateObject private var api = TeslaAPI.shared
    @State private var tab = 0

    var body: some View {
        Group {
            if api.loggedIn {
                ZStack(alignment: .bottom) {
                    switch tab {
                    case 0: HomeView(api: api)
                    case 1: TripsView(api: api)
                    case 2: PlaceholderView(title: "数据", icon: "chart.bar",
                                            note: "能耗趋势、月度统计")
                    case 3: ChargeDetailView(api: api)
                    default: PlaceholderView(title: "我的", icon: "person",
                                             note: "账号、密钥、自动锁设置")
                    }
                    TabBar(selected: $tab)
                }
            } else {
                LoginView(api: api)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            // 蓝牙先启动：不依赖网络和登录，飞行模式下也能开关车门
            TeslaKey.shared.start()
            Task { await api.restore() }
        }
    }
}

// MARK: - 底部标签栏

struct TabBar: View {
    @Binding var selected: Int
    private let items: [(String, String)] = [
        ("车辆", "car.fill"),
        ("地图", "map"),
        ("数据", "chart.bar"),
        ("充电", "bolt.fill"),
        ("我的", "person"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                Button {
                        Haptics.selection()
                        withAnimation(.easeOut(duration: 0.15)) { selected = idx }
                    } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.1)
                            .font(.system(size: 19, weight: .light))
                        Text(item.0).font(.system(size: 9.5, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(selected == idx ? L.sand : L.dim)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 26)
        .background(
            L.card
                .overlay(Rectangle().fill(L.line).frame(height: 1), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

// MARK: - 占位页

struct PlaceholderView: View {
    let title: String
    let icon: String
    let note: String

    var body: some View {
        ZStack {
            L.bg.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 44, weight: .light))
                    .foregroundColor(L.sub.opacity(0.6))
                Text(title).font(.system(size: 19, weight: .semibold)).foregroundColor(L.text)
                Text(note).font(.system(size: 13)).foregroundColor(L.sub)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 80)
        }
    }
}
