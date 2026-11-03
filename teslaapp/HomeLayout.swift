import SwiftUI
import Combine

/// 首页卡片：可折叠、可排序、可隐藏（全部持久化）
final class HomeLayout: ObservableObject {
    static let shared = HomeLayout()

    enum Card: String, CaseIterable, Identifiable {
        case car, battery, today, actions, charging, phoneKey, location
        var id: String { rawValue }

        var title: String {
            switch self {
            case .car:      return "车辆"
            case .battery:  return "电量与续航"
            case .today:    return "今日行程"
            case .actions:  return "快捷操作"
            case .charging: return "充电状态"
            case .phoneKey: return "手机钥匙"
            case .location: return "车在哪"
            }
        }

        var icon: String {
            switch self {
            case .car:      return "car.fill"
            case .battery:  return "battery.75"
            case .today:    return "chart.bar.fill"
            case .actions:  return "bolt.fill"
            case .charging: return "bolt.car.fill"
            case .phoneKey: return "key.fill"
            case .location: return "map.fill"
            }
        }
    }

    private let orderKey = "home.card.order"
    private let collapsedKey = "home.card.collapsed"
    private let hiddenKey = "home.card.hidden"

    @Published var order: [String]
    @Published var collapsed: Set<String>
    @Published var hidden: Set<String>

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: orderKey) ?? []
        let known = Set(Card.allCases.map(\.rawValue))
        // 补上新增的卡片（升级后如果加了新卡，自动追加到末尾）
        var merged = saved.filter { known.contains($0) }
        for c in Card.allCases.map(\.rawValue) where !merged.contains(c) { merged.append(c) }
        order = merged
        collapsed = Set(UserDefaults.standard.stringArray(forKey: collapsedKey) ?? [])

        hidden = Set(UserDefaults.standard.stringArray(forKey: hiddenKey) ?? [])
        if ProcessInfo.processInfo.environment["DEMO_LAYOUT"] == "1" {
            collapsed = ["today"]; hidden = ["phoneKey"]
        }
    }

    func move(_ id: String, by delta: Int) {
        guard let i = order.firstIndex(of: id) else { return }
        let j = i + delta
        guard order.indices.contains(j) else { return }
        order.swapAt(i, j)
        save()
    }

    func toggleCollapse(_ id: String) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
        save()
    }

    func toggleHidden(_ id: String) {
        if hidden.contains(id) { hidden.remove(id) } else { hidden.insert(id) }
        save()
    }

    func reset() {
        order = Card.allCases.map(\.rawValue)
        collapsed = []
        hidden = []
        save()
    }

    func title(_ id: String) -> String { Card(rawValue: id)?.title ?? id }
    func icon(_ id: String) -> String { Card(rawValue: id)?.icon ?? "square" }

    private func save() {
        UserDefaults.standard.set(order, forKey: orderKey)
        UserDefaults.standard.set(Array(collapsed), forKey: collapsedKey)
        UserDefaults.standard.set(Array(hidden), forKey: hiddenKey)
    }
}
