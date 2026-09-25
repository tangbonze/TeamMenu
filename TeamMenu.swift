import SwiftUI
import AppKit

// MARK: - Config

struct AppConfig {
    var apiKey: String
    var baseURL: URL
    var refreshInterval: TimeInterval
    var username: String?
}

func loadConfig() -> AppConfig {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser
    var apiKey: String? = nil
    var baseURLString = "https://api.teamorouter.cn/v1"
    var refreshInterval: TimeInterval = 60
    var username: String? = nil

    let configPath = home.appendingPathComponent("Library/Application Support/TeamMenu/config.json")
    if let data = try? Data(contentsOf: configPath),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        if let k = obj["api_key"] as? String, !k.isEmpty { apiKey = k }
        if let b = obj["base_url"] as? String, !b.isEmpty { baseURLString = b }
        if let r = obj["refresh_interval"] as? Double, r > 0 { refreshInterval = r }
        if let u = obj["username"] as? String, !u.isEmpty { username = u }
    }

    if apiKey == nil {
        let sessionPath = home.appendingPathComponent("Library/Application Support/com.teamolab.teamorouter/login-session.json")
        if let data = try? Data(contentsOf: sessionPath),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let account = obj["account"] as? [String: Any] {
            if let k = account["apiKey"] as? String { apiKey = k }
            if let u = account["username"] as? String, username == nil { username = u }
        }
    }

    if apiKey == nil { apiKey = ProcessInfo.processInfo.environment["TEAMO_API_KEY"] }
    if let b = ProcessInfo.processInfo.environment["TEAMO_BASE_URL"], !b.isEmpty { baseURLString = b }
    if let r = ProcessInfo.processInfo.environment["TEAMO_REFRESH_INTERVAL"], let rv = Double(r), rv > 0 { refreshInterval = rv }

    let key = apiKey ?? ""
    let base = URL(string: baseURLString) ?? URL(string: "https://api.teamorouter.cn/v1")!
    return AppConfig(apiKey: key, baseURL: base, refreshInterval: refreshInterval, username: username)
}

// MARK: - API models

struct BillingBalanceResponse: Decodable {
    struct Balance: Decodable {
        let value: String
        let currency: String?
    }
    let balance: Balance
}

struct UsageResponse: Decodable {
    struct Tokens: Decodable {
        let inputTokens: Int
        let cachedWriteTokens: Int
        let outputTokens: Int
        let cachedReadTokens: Int
        let totalTokens: Int
        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case cachedWriteTokens = "cached_write_tokens"
            case outputTokens = "output_tokens"
            case cachedReadTokens = "cached_read_tokens"
            case totalTokens = "total_tokens"
        }
    }
    let startTime: Int
    let endTime: Int
    let usage: Tokens
    let requests: Int
    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
        case usage
        case requests
    }
}

struct UserBalanceResponse: Decodable {
    let userId: String?
    let isActive: Bool?
    let status: String?
    let currency: String?
    let totalBalance: String?
    let availableBalance: String?
    let lifetimeSpent: String?
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case isActive = "is_active"
        case status
        case currency
        case totalBalance = "total_balance"
        case availableBalance = "available_balance"
        case lifetimeSpent = "lifetime_spent"
    }
}

// MARK: - API client

struct APIError: Error, LocalizedError {
    let status: Int
    let body: String
    var errorDescription: String? {
        body.isEmpty ? "HTTP \(status)" : "HTTP \(status): \(body)"
    }
}

final class APIClient {
    let base: URL
    let key: String
    private let session: URLSession

    init(config: AppConfig) {
        self.base = config.baseURL
        self.key = config.apiKey
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: cfg)
    }

    func get<T: Decodable>(_ path: String, query: [String: String]) async throws -> T {
        var urlString = base.absoluteString
        if !urlString.hasSuffix("/") { urlString += "/" }
        urlString += path
        var comps = URLComponents(string: urlString)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError(status: -1, body: "无网络响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw APIError(status: http.statusCode, body: msg)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Data

struct DayUsage: Identifiable {
    let date: Date
    let totalTokens: Int
    let requests: Int
    var id: Date { date }
}

enum Scheme: String, CaseIterable, Identifiable {
    case card
    case minimal
    case dashboard
    var id: String { rawValue }
    var name: String {
        switch self {
        case .card: return "卡片"
        case .minimal: return "极简"
        case .dashboard: return "仪表"
        }
    }
}

// MARK: - Panel metrics

enum PanelMetrics {
    static let width: CGFloat = 340
    static let height: CGFloat = 440
}

// MARK: - Store

@MainActor
final class Store: ObservableObject {
    @Published var balance: Double? = nil
    @Published var currency = "USD"
    @Published var usage: UsageResponse? = nil
    @Published var userBalance: UserBalanceResponse? = nil
    @Published var week: [DayUsage] = []
    @Published var lastUpdated: Date? = nil
    @Published var error: String? = nil
    @Published var isLoading = false
    @Published var scheme: Scheme

    let config: AppConfig
    private let client: APIClient?
    private var timer: Timer?

    var title: String {
        if let b = balance { return String(format: "$%.2f", b) }
        return error == nil ? "…" : "⚠︎"
    }

    var statusColor: Color {
        if error != nil { return .red }
        if balance == nil { return .yellow }
        return .green
    }

    init() {
        let cfg = loadConfig()
        self.config = cfg
        self.client = APIClient(config: cfg)
        self.scheme = Scheme(rawValue: UserDefaults.standard.string(forKey: "scheme") ?? "") ?? .card
    }

    func start() {
        guard timer == nil else { return }
        loadPersistedState()
        timer = Timer.scheduledTimer(withTimeInterval: config.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { @MainActor in await self.refresh() }
    }

    func refresh() async {
        guard let client, !config.apiKey.isEmpty else {
            error = "未找到 API Key，请配置 ~/Library/Application Support/TeamMenu/config.json"
            return
        }
        isLoading = true
        let now = Date()
        let cal = Calendar.current
        let start = Int(cal.startOfDay(for: now).timeIntervalSince1970)
        let end = Int(now.timeIntervalSince1970)
        do {
            let b: BillingBalanceResponse = try await client.get("billing/balance", query: [:], )
            let u: UsageResponse = try await client.get("usage", query: ["start_time": "\(start)", "end_time": "\(end)"], )
            let uu: UserBalanceResponse = try await client.get("user/balance", query: [:], )
            balance = Double(b.balance.value)
            currency = b.balance.currency ?? "USD"
            usage = u
            userBalance = uu
            lastUpdated = now
            error = nil

            var days: [DayUsage] = []
            for i in stride(from: 6, through: 1, by: -1) {
                guard let raw = cal.date(byAdding: .day, value: -i, to: now) else { continue }
                let ds = cal.startOfDay(for: raw)
                guard let de = cal.date(byAdding: .day, value: 1, to: ds) else { continue }
                if let r: UsageResponse = try? await client.get("usage",
                    query: ["start_time": "\(Int(ds.timeIntervalSince1970))", "end_time": "\(Int(de.timeIntervalSince1970))"]) {
                    days.append(DayUsage(date: ds, totalTokens: r.usage.totalTokens, requests: r.requests))
                }
            }
            days.append(DayUsage(date: cal.startOfDay(for: now), totalTokens: u.usage.totalTokens, requests: u.requests))
            week = days
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
        persistState()
    }

    // MARK: Persistence

    private func stateFileURL() -> URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let d = dir.appendingPathComponent("TeamMenu", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("state.json")
    }

    private func persistState() {
        guard let url = stateFileURL() else { return }
        var dict: [String: Any] = [
            "balance": balance.map { String(format: "%.8f", $0) } ?? NSNull(),
            "currency": currency,
            "last_updated": lastUpdated?.timeIntervalSince1970 ?? 0,
            "error": error ?? "",
        ]
        if let u = usage {
            dict["today"] = [
                "requests": u.requests,
                "input_tokens": u.usage.inputTokens,
                "output_tokens": u.usage.outputTokens,
                "cached_read_tokens": u.usage.cachedReadTokens,
                "cached_write_tokens": u.usage.cachedWriteTokens,
                "total_tokens": u.usage.totalTokens,
            ]
        }
        if !week.isEmpty {
            dict["week"] = week.map { [
                "date": $0.date.timeIntervalSince1970,
                "total_tokens": $0.totalTokens,
                "requests": $0.requests,
            ] }
        }
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
    }

    func loadPersistedState() {
        guard let url = stateFileURL(),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let b = obj["balance"] as? Double { balance = b }
        if let c = obj["currency"] as? String, !c.isEmpty { currency = c }
        if let ts = obj["last_updated"] as? Double { lastUpdated = Date(timeIntervalSince1970: ts) }
        if let e = obj["error"] as? String, !e.isEmpty { error = e }
        if let weekArr = obj["week"] as? [[String: Any]] {
            var days: [DayUsage] = []
            for item in weekArr {
                if let ts = item["date"] as? Double, let tot = item["total_tokens"] as? Int, let req = item["requests"] as? Int {
                    days.append(DayUsage(date: Date(timeIntervalSince1970: ts), totalTokens: tot, requests: req))
                }
            }
            if !days.isEmpty { week = days }
        }
    }
}

// MARK: - Shared components

struct Row: View {
    let label: String
    let value: String
    var bold = false
    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: bold ? .bold : .semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 7)
    }
}

struct FooterBar: View {
    @ObservedObject var store: Store

    private func timeText(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }

    var body: some View {
        VStack(spacing: 8) {
            if let e = store.error {
                Text("⚠︎ \(e)").font(.caption).foregroundColor(.red).lineLimit(2).multilineTextAlignment(.center)
            }
            if let t = store.lastUpdated {
                Text("更新于 \(timeText(t)) · 每 \(Int(store.config.refreshInterval)) 秒自动刷新")
                    .font(.caption2).foregroundColor(.secondary)
            }
            HStack(spacing: 8) {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("刷新")

                Button {
                    if let url = URL(string: "https://teamorouter.cn") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "safari")
                }
                .buttonStyle(.bordered)
                .help("打开官网")

                Spacer()

                Picker("", selection: $store.scheme) {
                    ForEach(Scheme.allCases) { s in Text(s.name).tag(s) }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)

                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.bordered)
                .help("退出 TeamMenu")
            }
        }
    }
}

// MARK: - 方案 A：卡片风

struct CardPanel: View {
    @ObservedObject var store: Store
    @Environment(\.colorScheme) private var cs

    private func fmt(_ n: Int) -> String {
        if n >= 100_000_000 { return String(format: "%.2f亿", Double(n) / 100_000_000) }
        if n >= 1_000_000 { return String(format: "%.2fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    private var balanceText: String {
        store.balance.map { String(format: "$%.2f", $0) } ?? "…"
    }

    private var heroGradient: [Color] {
        if cs == .dark {
            return [Color(red: 0.13, green: 0.36, blue: 0.88), Color(red: 0.04, green: 0.11, blue: 0.42)]
        }
        return [Color(red: 0.16, green: 0.45, blue: 0.95), Color(red: 0.05, green: 0.18, blue: 0.55)]
    }

    var body: some View {
        VStack(spacing: 0) {
            hero
            Spacer(minLength: 10)
            statGrid
            Spacer(minLength: 10)
            weekChart
            Spacer(minLength: 10)
            FooterBar(store: store)
        }
        .padding(12)
        .frame(width: PanelMetrics.width, height: PanelMetrics.height)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var hero: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("TeamoRouter 余额").font(.caption).foregroundColor(.white.opacity(0.85))
                Text(balanceText)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                if let u = store.config.username, !u.isEmpty {
                    Text("账户 \(u)").font(.caption2).foregroundColor(.white.opacity(0.7))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Circle().fill(store.statusColor).frame(width: 10, height: 10)
                if let ub = store.userBalance, let st = ub.status {
                    Text(st).font(.caption2).foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding(16)
        .background(LinearGradient(colors: heroGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: cs == .dark ? .black.opacity(0.3) : .blue.opacity(0.25), radius: 10, y: 4)
    }

    @ViewBuilder private var statGrid: some View {
        if let u = store.usage {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                StatTile(icon: "paperplane.fill", tint: .blue, label: "今日请求", value: "\(u.requests)")
                StatTile(icon: "arrow.up.circle.fill", tint: .green, label: "输入", value: fmt(u.usage.inputTokens))
                StatTile(icon: "arrow.down.circle.fill", tint: .orange, label: "输出", value: fmt(u.usage.outputTokens))
                StatTile(icon: "bolt.fill", tint: .purple, label: "缓存读写", value: fmt(u.usage.cachedReadTokens + u.usage.cachedWriteTokens))
            }
        } else {
            Text(store.isLoading ? "加载中…" : "暂无数据")
                .font(.caption).foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    private var weekChart: some View {
        let peak = store.week.map(\.totalTokens).max() ?? 1
        let sum = store.week.map(\.totalTokens).reduce(0, +)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("近 7 日用量").font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("总 \(fmt(sum))").font(.caption2).foregroundColor(.secondary)
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(store.week) { d in
                    VStack(spacing: 3) {
                        Capsule()
                            .fill(
                                LinearGradient(colors: [.blue, .cyan], startPoint: .bottom, endPoint: .top)
                            )
                            .frame(width: 10, height: max(3, 48 * CGFloat(d.totalTokens) / CGFloat(peak)))
                        Text(dayLabel(d.date))
                            .font(.system(size: 9, weight: d.date.isToday ? .bold : .regular))
                            .foregroundColor(d.date.isToday ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 64)
        }
        .padding(10)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func dayLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEEEE"
        return f.string(from: d)
    }
}

struct StatTile: View {
    let icon: String
    let tint: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2).foregroundColor(.secondary)
                Text(value).font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - 方案 B：极简风

struct MinimalPanel: View {
    @ObservedObject var store: Store

    private func fmt(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.2fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TeamoRouter").font(.title3.weight(.bold))
                    if let u = store.config.username, !u.isEmpty {
                        Text("账户 \(u)").font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Circle().fill(store.statusColor).frame(width: 9, height: 9)
            }
            .padding(.bottom, 6)

            Divider()

            Spacer(minLength: 8)
            if let b = store.balance {
                Row(label: "余额", value: String(format: "$%.2f", b), bold: true)
            }
            if let ub = store.userBalance {
                if let spent = ub.lifetimeSpent, let v = Double(spent), v > 0 {
                    Row(label: "累计消费", value: String(format: "$%.4f", v))
                }
            }
            Spacer(minLength: 8)
            Divider()

            Text("今日用量").font(.caption).foregroundColor(.secondary).padding(.top, 8)
            if let u = store.usage {
                Row(label: "请求数", value: "\(u.requests)")
                Row(label: "总 Tokens", value: fmt(u.usage.totalTokens))
                Row(label: "输入", value: fmt(u.usage.inputTokens))
                Row(label: "输出", value: fmt(u.usage.outputTokens))
                Row(label: "缓存读 / 写", value: "\(fmt(u.usage.cachedReadTokens)) / \(fmt(u.usage.cachedWriteTokens))")
            } else {
                Text(store.isLoading ? "加载中…" : "暂无数据").font(.caption).foregroundColor(.secondary)
            }

            if !store.week.isEmpty {
                miniBars
            }
            Spacer(minLength: 8)
            Divider()

            Spacer(minLength: 8)
            FooterBar(store: store)
        }
        .padding(12)
        .frame(width: PanelMetrics.width, height: PanelMetrics.height)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var miniBars: some View {
        let peak = store.week.map(\.totalTokens).max() ?? 1
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(store.week) { d in
                RoundedRectangle(cornerRadius: 2)
                    .fill(d.date.isToday ? Color.accentColor : Color.secondary.opacity(0.5))
                    .frame(width: 12, height: max(3, 30 * CGFloat(d.totalTokens) / CGFloat(peak)))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .padding(.top, 6)
    }
}

// MARK: - 方案 C：仪表盘

struct DashboardPanel: View {
    @ObservedObject var store: Store
    @Environment(\.colorScheme) private var cs

    private var isDark: Bool { cs == .dark }

    private func fmt(_ n: Int) -> String {
        if n >= 100_000_000 { return String(format: "%.2f亿", Double(n) / 100_000_000) }
        if n >= 1_000_000 { return String(format: "%.2fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    private func adaptive(_ light: Color, _ dark: Color) -> Color {
        isDark ? dark : light
    }

    private var ringGradient: [Color] {
        isDark ? [.cyan, .blue, .purple] : [.blue, .indigo, .purple]
    }

    private var ringProgress: CGFloat {
        guard let today = store.usage, !store.week.isEmpty else { return 0 }
        let peak = store.week.map(\.totalTokens).max() ?? 1
        return min(1, CGFloat(today.usage.totalTokens) / CGFloat(peak))
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("TeamoRouter 仪表盘").font(.headline).foregroundColor(.primary)

            Spacer(minLength: 8)
            ZStack {
                Circle().stroke(Color.primary.opacity(0.10), lineWidth: 13)
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(
                        AngularGradient(colors: ringGradient, center: .center),
                        style: StrokeStyle(lineWidth: 13, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 3) {
                    Text(store.balance.map { String(format: "$%.2f", $0) } ?? "…")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("今日用量 / 近7日峰值")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .frame(width: 150, height: 150)

            Spacer(minLength: 8)
            if let u = store.usage {
                VStack(spacing: 8) {
                    dashRow(icon: "paperplane.fill", color: adaptive(.blue, .cyan), label: "请求数", value: "\(u.requests)")
                    dashRow(icon: "arrow.up.circle.fill", color: .green, label: "输入", value: fmt(u.usage.inputTokens))
                    dashRow(icon: "arrow.down.circle.fill", color: .orange, label: "输出", value: fmt(u.usage.outputTokens))
                    dashRow(icon: "bolt.fill", color: .purple, label: "缓存读写", value: fmt(u.usage.cachedReadTokens + u.usage.cachedWriteTokens))
                }
            } else {
                Text(store.isLoading ? "加载中…" : "暂无数据")
                    .font(.caption).foregroundColor(.secondary)
            }

            Spacer(minLength: 8)
            FooterBar(store: store)
        }
        .padding(14)
        .frame(width: PanelMetrics.width, height: PanelMetrics.height)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func dashRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundColor(color)
                .frame(width: 20)
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

// MARK: - Panel

struct PanelView: View {
    @ObservedObject var store: Store

    var body: some View {
        switch store.scheme {
        case .card:
            CardPanel(store: store)
        case .minimal:
            MinimalPanel(store: store)
        case .dashboard:
            DashboardPanel(store: store)
        }
    }
}

// MARK: - App

@main
struct TeamMenuApp: App {
    @StateObject private var store = Store()

    init() {
        let s = Store()
        _store = StateObject(wrappedValue: s)
        // 确保不显示在 Dock（与 Info.plist 的 LSUIElement 双重保险）
        NSApplication.shared.setActivationPolicy(.accessory)
        s.start()
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(store: store)
        } label: {
            HStack(spacing: 4) {
                Circle().fill(store.statusColor).frame(width: 7, height: 7)
                Text(store.title)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

private extension Date {
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }
}
