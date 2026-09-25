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

/// Accepts either a JSON number or a numeric string.
struct FlexDouble: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = Double(s) }
        else { value = nil }
    }
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

/// /v1/billing/me/balance — richer than /v1/billing/balance
struct RichBalanceResponse: Decodable {
    let data: RichBalance?
    struct RichBalance: Decodable {
        let userId: String?
        let totalBalance: Double?
        let frozenBalance: Double?
        let availableBalance: Double?
        let lifetimeSpent: Double?
        let currency: String?
        let status: String?
        let expiredTimeDeadline: Double?
        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case totalBalance, frozenBalance, availableBalance, lifetimeSpent, currency, status
            case expiredTimeDeadline = "expired_time_deadline"
        }
    }
}

/// /v1/billing/me/transactions — per-request billing records
struct TransactionsResponse: Decodable {
    let data: Payload?
    struct Payload: Decodable {
        let transactions: [Tx]?
        let totalCount: Int?
        let totalPages: Int?
        let page: Int?
        enum CodingKeys: String, CodingKey {
            case transactions
            case totalCount = "total_count"
            case totalPages = "total_pages"
            case page
        }
    }
    struct Tx: Decodable {
        let txId: String
        let productId: String?
        let routingQueueModel: String?
        let clientSource: String?
        let amount: FlexDouble?
        let listCost: FlexDouble?
        let promptTokens: Int?
        let completionTokens: Int?
        let cachedInputTokens: Int?
        let createdAt: String?
        let type: String?
        enum CodingKeys: String, CodingKey {
            case txId = "tx_id"
            case productId = "product_id"
            case routingQueueModel = "routing_queue_model"
            case clientSource = "client_source"
            case amount
            case listCost = "list_cost"
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case cachedInputTokens = "cached_input_tokens"
            case createdAt = "created_at"
            case type
        }
    }
}

/// /v1/billing/sla/overview — per-model availability
struct SLAResponse: Decodable {
    let data: Payload?
    struct Payload: Decodable { let items: [Item]? }
    struct Item: Decodable, Identifiable {
        let model: String
        let sla: Double?
        let successCount: Int?
        let requestCount: Int?
        var id: String { model }
        enum CodingKeys: String, CodingKey {
            case model, sla
            case successCount = "success_count"
            case requestCount = "request_count"
        }
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
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 25
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

// MARK: - Local models

struct TxRecord: Identifiable {
    let id: String
    let date: Date?
    let model: String
    let cost: Double
    let tokens: Int
    let cachedTokens: Int
    let clientSource: String?
    let type: String          // COMMIT = 实际消费, RECHARGE = 充值
    var isSpend: Bool { type == "COMMIT" }
    var isRecharge: Bool { type == "RECHARGE" }
}

struct ModelAgg: Identifiable {
    let model: String
    var requests: Int
    var tokens: Int
    var cost: Double
    var id: String { model }
}

struct DayAgg: Identifiable {
    let date: Date
    var cost: Double
    var tokens: Int
    var requests: Int
    var covered: Bool = true   // false = 超出可回溯范围，无数据
    var id: Date { date }
}

enum Scheme: String, CaseIterable, Identifiable {
    case card, minimal, dashboard
    var id: String { rawValue }
    var name: String {
        switch self {
        case .card: return "卡片"
        case .minimal: return "极简"
        case .dashboard: return "仪表"
        }
    }
}

enum PanelTab: String, CaseIterable, Identifiable {
    case overview, transactions, models, health
    var id: String { rawValue }
    var name: String {
        switch self {
        case .overview: return "概览"
        case .transactions: return "明细"
        case .models: return "模型"
        case .health: return "健康"
        }
    }
}

// MARK: - Store

@MainActor
final class Store: ObservableObject {
    // balance
    @Published var balance: Double? = nil
    @Published var currency = "USD"
    @Published var frozen: Double? = nil
    @Published var available: Double? = nil
    @Published var lifetimeSpent: Double? = nil
    @Published var accountStatus: String? = nil

    // usage
    @Published var usage: UsageResponse? = nil
    @Published var today: DayAgg? = nil
    @Published var week: [DayAgg] = []
    @Published var byModelToday: [ModelAgg] = []

    // billing detail
    @Published var transactions: [TxRecord] = []
    @Published var txTotalCount: Int? = nil
    @Published var sla: [SLAResponse.Item] = []

    // ui
    @Published var lastUpdated: Date? = nil
    @Published var error: String? = nil
    @Published var isLoading = false
    @Published var scheme: Scheme
    @Published var tab: PanelTab

    let config: AppConfig
    private let client: APIClient?
    private var timer: Timer?
    private var lastSLAFetch: Date?
    /// 交易记录本地缓存（tx_id -> record），用于增量拉取
    private var txCache: [String: TxRecord] = [:]
    private var txBackfilled = false
    private var historyComplete = true

    var statusColor: Color {
        if error != nil { return .red }
        if balance == nil { return .yellow }
        return .green
    }

    var title: String {
        if let b = balance { return String(format: "$%.2f", b) }
        return error == nil ? "…" : "⚠︎"
    }

    init() {
        let cfg = loadConfig()
        self.config = cfg
        self.client = APIClient(config: cfg)
        self.scheme = Scheme(rawValue: UserDefaults.standard.string(forKey: "scheme") ?? "") ?? .card
        self.tab = PanelTab(rawValue: UserDefaults.standard.string(forKey: "tab") ?? "") ?? .overview
    }

    func start() {
        guard timer == nil else { return }
        loadPersistedState()
        timer = Timer.scheduledTimer(withTimeInterval: config.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { @MainActor in await self.refresh() }
    }

    // MARK: Refresh

    func refresh() async {
        guard let client, !config.apiKey.isEmpty else {
            error = "未找到 API Key，请配置 ~/Library/Application Support/TeamMenu/config.json"
            return
        }
        isLoading = true
        let now = Date()
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)

        do {
            // 1. rich balance
            let rb: RichBalanceResponse = try await client.get("billing/me/balance", query: [:])
            if let d = rb.data {
                balance = d.totalBalance
                frozen = d.frozenBalance
                available = d.availableBalance
                lifetimeSpent = d.lifetimeSpent
                currency = d.currency ?? currency
                accountStatus = d.status
            }

            // 2. today's aggregate usage
            let start = Int(dayStart.timeIntervalSince1970)
            let end = Int(now.timeIntervalSince1970)
            let u: UsageResponse = try await client.get("usage", query: ["start_time": "\(start)", "end_time": "\(end)"])
            usage = u

            // 3. transaction records — incremental: full backfill once, then newest pages only.
            //    (the API ignores page_size and always returns 20 per page)
            let cutoff = cal.date(byAdding: .day, value: -6, to: dayStart) ?? dayStart
            let maxPages = txBackfilled ? 2 : 40
            var page = 1
            var total: Int? = nil
            var reachedCutoff = false
            while page <= maxPages {
                let r: TransactionsResponse = try await client.get(
                    "billing/me/transactions",
                    query: ["page": "\(page)", "page_size": "20"]
                )
                let txs = r.data?.transactions ?? []
                if page == 1 { total = r.data?.totalCount }
                if txs.isEmpty { break }
                for t in txs {
                    let rec = TxRecord(
                        id: t.txId,
                        date: Self.parseDate(t.createdAt),
                        model: t.productId ?? t.routingQueueModel ?? "unknown",
                        cost: t.amount?.value ?? 0,
                        tokens: (t.promptTokens ?? 0) + (t.completionTokens ?? 0),
                        cachedTokens: t.cachedInputTokens ?? 0,
                        clientSource: t.clientSource,
                        type: t.type ?? "COMMIT"
                    )
                    txCache[rec.id] = rec
                }
                if let oldest = txs.compactMap({ Self.parseDate($0.createdAt) }).min(), oldest < cutoff {
                    reachedCutoff = true
                    break
                }
                if let tp = r.data?.totalPages, page >= tp { reachedCutoff = true; break }
                page += 1
            }
            if !txBackfilled { historyComplete = reachedCutoff }
            txBackfilled = true
            txCache = txCache.filter { entry in
                guard let d = entry.value.date else { return true }
                return d >= cutoff
            }
            let records = txCache.values.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            transactions = records
            txTotalCount = total

            // 4. aggregates
            let todayRecords = records.filter { rec in
                guard rec.isSpend, let d = rec.date else { return false }
                return cal.isDate(d, inSameDayAs: now)
            }
            let todayCost = todayRecords.reduce(0) { $0 + $1.cost }
            let todayTokens = todayRecords.reduce(0) { $0 + $1.tokens }
            today = DayAgg(date: dayStart, cost: todayCost, tokens: todayTokens, requests: todayRecords.count)

            var agg: [String: ModelAgg] = [:]
            for rec in todayRecords {
                var m = agg[rec.model] ?? ModelAgg(model: rec.model, requests: 0, tokens: 0, cost: 0)
                m.requests += 1
                m.tokens += rec.tokens
                m.cost += rec.cost
                agg[rec.model] = m
            }
            byModelToday = agg.values.sorted { $0.cost > $1.cost }

            var days: [DayAgg] = []
            for i in stride(from: 6, through: 0, by: -1) {
                guard let d = cal.date(byAdding: .day, value: -i, to: dayStart) else { continue }
                let recs = records.filter { rec in
                    guard rec.isSpend, let rd = rec.date else { return false }
                    return cal.isDate(rd, inSameDayAs: d)
                }
                let oldest = records.compactMap({ $0.date }).min()
                let covered = historyComplete || (oldest.map { d >= cal.startOfDay(for: $0) } ?? true)
                days.append(DayAgg(
                    date: d,
                    cost: recs.reduce(0) { $0 + $1.cost },
                    tokens: recs.reduce(0) { $0 + $1.tokens },
                    requests: recs.count,
                    covered: covered
                ))
            }
            week = days

            // 5. SLA (throttled to every 5 minutes)
            if lastSLAFetch == nil || now.timeIntervalSince(lastSLAFetch!) > 300 {
                if let s: SLAResponse = try? await client.get("billing/sla/overview", query: [:]) {
                    sla = (s.data?.items ?? []).filter { ($0.requestCount ?? 0) > 0 }
                    lastSLAFetch = now
                }
            }

            lastUpdated = now
            error = nil
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
        persistState()
    }

    static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
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
        if let t = today {
            dict["today"] = ["cost": t.cost, "tokens": t.tokens, "requests": t.requests]
        }
        if !week.isEmpty {
            dict["week"] = week.map { ["date": $0.date.timeIntervalSince1970, "cost": $0.cost, "tokens": $0.tokens, "requests": $0.requests] }
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
        if let weekArr = obj["week"] as? [[String: Any]] {
            var days: [DayAgg] = []
            for item in weekArr {
                if let ts = item["date"] as? Double {
                    days.append(DayAgg(
                        date: Date(timeIntervalSince1970: ts),
                        cost: item["cost"] as? Double ?? 0,
                        tokens: item["tokens"] as? Int ?? 0,
                        requests: item["requests"] as? Int ?? 0
                    ))
                }
            }
            if !days.isEmpty { week = days }
        }
    }
}

// MARK: - Formatting helpers

enum Fmt {
    static func money(_ v: Double?) -> String {
        guard let v else { return "—" }
        if v == 0 { return "$0.00" }
        if v < 0.01 { return String(format: "$%.6f", v) }
        if v < 1 { return String(format: "$%.4f", v) }
        return String(format: "$%.2f", v)
    }

    static func balance(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(format: "$%.2f", v)
    }

    static func tokens(_ n: Int) -> String {
        if n >= 100_000_000 { return String(format: "%.2f亿", Double(n) / 100_000_000) }
        if n >= 1_000_000 { return String(format: "%.2fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    static func time(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f.string(from: d)
    }

    static func clock(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }

    static func weekday(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEEEE"
        return f.string(from: d)
    }

    static func percent(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(format: "%.2f%%", v)
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
        .padding(.vertical, 6)
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

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(title).font(.caption).foregroundColor(.secondary)
            Spacer()
            if let trailing { Text(trailing).font(.caption2).foregroundColor(.secondary) }
        }
    }
}

struct FooterBar: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(spacing: 8) {
            if let e = store.error {
                Text("⚠︎ \(e)").font(.caption).foregroundColor(.red).lineLimit(2).multilineTextAlignment(.center)
            }
            if let t = store.lastUpdated {
                Text("更新于 \(Fmt.clock(t)) · 每 \(Int(store.config.refreshInterval)) 秒刷新")
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

                if store.tab == .overview {
                    Picker("", selection: $store.scheme) {
                        ForEach(Scheme.allCases) { s in Text(s.name).tag(s) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 168)
                }

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

// MARK: - 方案 A：卡片风（概览）

struct CardPanel: View {
    @ObservedObject var store: Store
    @Environment(\.colorScheme) private var cs

    private var heroGradient: [Color] {
        if cs == .dark {
            return [Color(red: 0.13, green: 0.36, blue: 0.88), Color(red: 0.04, green: 0.11, blue: 0.42)]
        }
        return [Color(red: 0.16, green: 0.45, blue: 0.95), Color(red: 0.05, green: 0.18, blue: 0.55)]
    }

    var body: some View {
        VStack(spacing: 0) {
            hero
            Spacer(minLength: 8)
            moneyRow
            Spacer(minLength: 8)
            statGrid
            Spacer(minLength: 8)
            weekChart
        }
        .padding(12)
    }

    private var hero: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("TeamoRouter 余额").font(.caption).foregroundColor(.white.opacity(0.85))
                Text(Fmt.balance(store.balance))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                if let u = store.config.username, !u.isEmpty {
                    Text("账户 \(u)").font(.caption2).foregroundColor(.white.opacity(0.7))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Circle().fill(store.statusColor).frame(width: 10, height: 10)
                if let st = store.accountStatus {
                    Text(st).font(.caption2).foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding(16)
        .background(LinearGradient(colors: heroGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: cs == .dark ? .black.opacity(0.3) : .blue.opacity(0.25), radius: 10, y: 4)
    }

    private var moneyRow: some View {
        HStack(spacing: 8) {
            moneyChip(title: "今日花费", value: Fmt.money(store.today?.cost), tint: .orange)
            moneyChip(title: "可用", value: Fmt.balance(store.available), tint: .green)
            moneyChip(title: "冻结", value: Fmt.balance(store.frozen), tint: .gray)
        }
    }

    private func moneyChip(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    @ViewBuilder private var statGrid: some View {
        if let u = store.usage {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                StatTile(icon: "paperplane.fill", tint: .blue, label: "今日请求", value: "\(u.requests)")
                StatTile(icon: "arrow.up.circle.fill", tint: .green, label: "输入", value: Fmt.tokens(u.usage.inputTokens))
                StatTile(icon: "arrow.down.circle.fill", tint: .orange, label: "输出", value: Fmt.tokens(u.usage.outputTokens))
                StatTile(icon: "bolt.fill", tint: .purple, label: "缓存读写", value: Fmt.tokens(u.usage.cachedReadTokens + u.usage.cachedWriteTokens))
            }
        } else {
            Text(store.isLoading ? "加载中…" : "暂无数据")
                .font(.caption).foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    private var weekChart: some View {
        let peak = max(store.week.map(\.cost).max() ?? 0, 0.000001)
        let sum = store.week.reduce(0) { $0 + $1.cost }
        return VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "近 7 日花费", trailing: "合计 \(Fmt.money(sum))")
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(store.week) { d in
                    VStack(spacing: 3) {
                        if d.covered {
                            Capsule()
                                .fill(LinearGradient(colors: [.orange, .yellow], startPoint: .bottom, endPoint: .top))
                                .frame(width: 10, height: max(3, 44 * CGFloat(d.cost / peak)))
                        } else {
                            Capsule()
                                .fill(Color.secondary.opacity(0.18))
                                .frame(width: 10, height: 3)
                        }
                        Text(Fmt.weekday(d.date))
                            .font(.system(size: 9, weight: Calendar.current.isDateInToday(d.date) ? .bold : .regular))
                            .foregroundColor(Calendar.current.isDateInToday(d.date) ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 58)
        }
        .padding(10)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 方案 B：极简风（概览）

struct MinimalPanel: View {
    @ObservedObject var store: Store

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
            Spacer(minLength: 6)
            Row(label: "余额", value: Fmt.balance(store.balance), bold: true)
            Row(label: "可用 / 冻结", value: "\(Fmt.balance(store.available)) / \(Fmt.balance(store.frozen))")
            Row(label: "累计消费", value: Fmt.money(store.lifetimeSpent))
            Row(label: "今日花费", value: Fmt.money(store.today?.cost), bold: true)
            Spacer(minLength: 6)
            Divider()
            Spacer(minLength: 6)

            Text("今日用量").font(.caption).foregroundColor(.secondary)
            if let u = store.usage {
                Row(label: "请求数", value: "\(u.requests)")
                Row(label: "总 Tokens", value: Fmt.tokens(u.usage.totalTokens))
                Row(label: "输入 / 输出", value: "\(Fmt.tokens(u.usage.inputTokens)) / \(Fmt.tokens(u.usage.outputTokens))")
                Row(label: "缓存读 / 写", value: "\(Fmt.tokens(u.usage.cachedReadTokens)) / \(Fmt.tokens(u.usage.cachedWriteTokens))")
            } else {
                Text(store.isLoading ? "加载中…" : "暂无数据").font(.caption).foregroundColor(.secondary)
            }
            Spacer(minLength: 6)

            if !store.week.isEmpty {
                miniBars
            }
        }
        .padding(12)
    }

    private var miniBars: some View {
        let peak = max(store.week.map(\.cost).max() ?? 0, 0.000001)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(store.week) { d in
                RoundedRectangle(cornerRadius: 2)
                    .fill(d.covered
                          ? (Calendar.current.isDateInToday(d.date) ? Color.accentColor : Color.secondary.opacity(0.5))
                          : Color.secondary.opacity(0.15))
                    .frame(width: 12, height: d.covered ? max(3, 26 * CGFloat(d.cost / peak)) : 3)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .padding(.top, 6)
    }
}

// MARK: - 方案 C：仪表盘（概览）

struct DashboardPanel: View {
    @ObservedObject var store: Store
    @Environment(\.colorScheme) private var cs

    private var isDark: Bool { cs == .dark }
    private func adaptive(_ light: Color, _ dark: Color) -> Color { isDark ? dark : light }

    private var ringGradient: [Color] {
        isDark ? [.cyan, .blue, .purple] : [.blue, .indigo, .purple]
    }

    private var ringProgress: CGFloat {
        guard let today = store.today else { return 0 }
        let peak = max(store.week.map(\.cost).max() ?? 0, 0.000001)
        return min(1, CGFloat(today.cost / peak))
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("TeamoRouter 仪表盘").font(.headline).foregroundColor(.primary)
            Spacer(minLength: 6)
            ZStack {
                Circle().stroke(Color.primary.opacity(0.10), lineWidth: 13)
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(AngularGradient(colors: ringGradient, center: .center),
                            style: StrokeStyle(lineWidth: 13, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 3) {
                    Text(Fmt.money(store.today?.cost))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("今日花费 / 近7日峰值")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .frame(width: 148, height: 148)

            Spacer(minLength: 6)
            VStack(spacing: 7) {
                dashRow(icon: "dollarsign.circle.fill", color: adaptive(.blue, .cyan), label: "余额", value: Fmt.balance(store.balance))
                dashRow(icon: "flame.fill", color: .orange, label: "今日花费", value: Fmt.money(store.today?.cost))
                dashRow(icon: "calendar", color: .purple, label: "累计消费", value: Fmt.money(store.lifetimeSpent))
                if let u = store.usage {
                    dashRow(icon: "paperplane.fill", color: adaptive(.green, .green), label: "今日请求", value: "\(u.requests)")
                    dashRow(icon: "bolt.fill", color: .teal, label: "今日 Tokens", value: Fmt.tokens(u.usage.totalTokens))
                }
            }
        }
        .padding(14)
    }

    private func dashRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundColor(color).frame(width: 20)
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

// MARK: - 明细

struct TransactionsPanel: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("今日花费").font(.caption).foregroundColor(.secondary)
                Text(Fmt.money(store.today?.cost))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.orange)
                Spacer()
                Text("共 \(store.txTotalCount ?? store.transactions.count) 笔")
                    .font(.caption2).foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if store.transactions.isEmpty {
                Spacer()
                Text(store.isLoading ? "加载中…" : "暂无交易记录")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(store.transactions) { tx in
                            HStack(spacing: 8) {
                                Image(systemName: tx.isRecharge ? "plus.circle.fill" : "arrow.up.right.circle")
                                    .font(.system(size: 12))
                                    .foregroundColor(tx.isRecharge ? .green : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tx.isRecharge ? "充值入账" : tx.model)
                                        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    Text(Fmt.time(tx.date)).font(.system(size: 10)).foregroundColor(.secondary)
                                }
                                Spacer(minLength: 4)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(tx.isRecharge ? "+" + Fmt.balance(abs(tx.cost)) : Fmt.money(tx.cost))
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(tx.isRecharge ? .green : .orange)
                                        .monospacedDigit()
                                    Text(tx.isRecharge ? "额度入账" : "\(Fmt.tokens(tx.tokens)) tok")
                                        .font(.system(size: 10)).foregroundColor(.secondary).monospacedDigit()
                                }
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

// MARK: - 模型

struct ModelsPanel: View {
    @ObservedObject var store: Store

    var body: some View {
        let totalCost = max(store.byModelToday.reduce(0) { $0 + $1.cost }, 0.000001)
        return VStack(spacing: 0) {
            HStack {
                Text("今日按模型").font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("合计 \(Fmt.money(store.today?.cost))")
                    .font(.caption2).foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if store.byModelToday.isEmpty {
                Spacer()
                Text(store.isLoading ? "加载中…" : "今日暂无用量")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(store.byModelToday) { m in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(m.model).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    Spacer()
                                    Text(Fmt.money(m.cost))
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(.orange).monospacedDigit()
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.08))
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                                            .frame(width: max(2, geo.size.width * CGFloat(m.cost / totalCost)))
                                    }
                                }
                                .frame(height: 4)
                                HStack {
                                    Text("\(m.requests) 次请求").font(.system(size: 10)).foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(Fmt.tokens(m.tokens)) tok").font(.system(size: 10)).foregroundColor(.secondary).monospacedDigit()
                                    Text(String(format: "%.1f%%", 100 * m.cost / totalCost))
                                        .font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

// MARK: - 健康

struct HealthPanel: View {
    @ObservedObject var store: Store

    private var sorted: [SLAResponse.Item] {
        store.sla.sorted { ($0.requestCount ?? 0) > ($1.requestCount ?? 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("模型服务健康度").font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("\(store.sla.count) 个模型")
                    .font(.caption2).foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if store.sla.isEmpty {
                Spacer()
                Text(store.isLoading ? "加载中…" : "暂无 SLA 数据（每 5 分钟更新）")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(sorted) { item in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(slaColor(item.sla))
                                    .frame(width: 7, height: 7)
                                Text(item.model).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(Fmt.percent(item.sla))
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(slaColor(item.sla))
                                    .monospacedDigit()
                                Text("\(item.successCount ?? 0)/\(item.requestCount ?? 0)")
                                    .font(.system(size: 10)).foregroundColor(.secondary).monospacedDigit()
                                    .frame(width: 62, alignment: .trailing)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func slaColor(_ v: Double?) -> Color {
        guard let v else { return .secondary }
        if v >= 99.5 { return .green }
        if v >= 98 { return .yellow }
        return .red
    }
}

// MARK: - Panel

enum PanelMetrics {
    static let width: CGFloat = 360
    static let height: CGFloat = 540
}

struct PanelView: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $store.tab) {
                ForEach(PanelTab.allCases) { t in Text(t.name).tag(t) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()

            Group {
                switch store.tab {
                case .overview:
                    switch store.scheme {
                    case .card: CardPanel(store: store)
                    case .minimal: MinimalPanel(store: store)
                    case .dashboard: DashboardPanel(store: store)
                    }
                case .transactions: TransactionsPanel(store: store)
                case .models: ModelsPanel(store: store)
                case .health: HealthPanel(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            FooterBar(store: store)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(width: PanelMetrics.width, height: PanelMetrics.height)
        .background(Color(nsColor: .windowBackgroundColor))
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
