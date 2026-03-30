import Foundation
import Combine

class DataStore: ObservableObject {
    @Published var buckets: [[BucketRates]] = DisplayMode.allCases.map { mode in
        Array(repeating: BucketRates.noData, count: mode.numBuckets)
    }
    @Published var incidents: [Int] = [0, 0, 0]
    @Published var status: CurrentStatus = CurrentStatus()
    @Published var lastEmailSent: String = "never"
    @Published var alertEmail: String = ""
    @Published var daemonRunning: Bool = false

    private let dataFile: URL
    private let statusFile: URL
    private let lastEmailFile: URL
    private var timer: Timer?

    init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NetworkWatch")
        dataFile     = support.appendingPathComponent("checks.csv")
        statusFile   = support.appendingPathComponent("status")
        lastEmailFile = support.appendingPathComponent("last-email.txt")

        loadEnvEmail()
        refresh()

        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            let rows   = self.parseCSV()
            let now    = Date().timeIntervalSince1970
            var newBuckets: [[BucketRates]] = []
            var newIncidents: [Int] = []
            for mode in DisplayMode.allCases {
                let (b, inc) = self.aggregate(rows: rows, mode: mode, now: now)
                newBuckets.append(b)
                newIncidents.append(inc)
            }
            let newStatus    = self.parseStatus()
            let newLastEmail = self.parseLastEmail()
            DispatchQueue.main.async {
                self.buckets      = newBuckets
                self.incidents    = newIncidents
                self.status       = newStatus
                self.lastEmailSent = newLastEmail
            }
        }
    }

    func parseCSV() -> [CheckRow] {
        guard let text = try? String(contentsOf: dataFile, encoding: .utf8) else { return [] }
        var rows: [CheckRow] = []
        for line in text.components(separatedBy: .newlines) {
            let parts = line.trimmingCharacters(in: .whitespaces)
                            .components(separatedBy: ",")
            guard parts.count >= 6,
                  let epoch = Double(parts[0]) else { continue }
            func b(_ i: Int) -> Bool { parts[i].trimmingCharacters(in: .whitespaces) == "1" }
            rows.append(CheckRow(epoch: epoch, wifi: b(1), router: b(2),
                                 internet: b(3), dns: b(4), web: b(5)))
        }
        return rows
    }

    func aggregate(rows: [CheckRow], mode: DisplayMode, now: Double) -> ([BucketRates], Int) {
        let windowStart = now - mode.windowSeconds
        let n = mode.numBuckets
        var overallCounts  = Array(repeating: (ok: 0, total: 0), count: n)
        var wifiCounts     = Array(repeating: (ok: 0, total: 0), count: n)
        var routerCounts   = Array(repeating: (ok: 0, total: 0), count: n)
        var internetCounts = Array(repeating: (ok: 0, total: 0), count: n)
        var dnsCounts      = Array(repeating: (ok: 0, total: 0), count: n)
        var webCounts      = Array(repeating: (ok: 0, total: 0), count: n)

        for row in rows {
            guard row.epoch >= windowStart else { continue }
            let offset = row.epoch - windowStart
            let idx = min(Int(offset / mode.bucketSeconds), n - 1)
            overallCounts[idx].total  += 1
            wifiCounts[idx].total     += 1
            routerCounts[idx].total   += 1
            internetCounts[idx].total += 1
            dnsCounts[idx].total      += 1
            webCounts[idx].total      += 1
            if row.allOK    { overallCounts[idx].ok  += 1 }
            if row.wifi     { wifiCounts[idx].ok     += 1 }
            if row.router   { routerCounts[idx].ok   += 1 }
            if row.internet { internetCounts[idx].ok += 1 }
            if row.dns      { dnsCounts[idx].ok      += 1 }
            if row.web      { webCounts[idx].ok      += 1 }
        }

        func rate(_ c: (ok: Int, total: Int)) -> Double {
            c.total == 0 ? -1.0 : Double(c.ok) / Double(c.total)
        }

        var result: [BucketRates] = []
        var incidentCount = 0
        for i in 0..<n {
            let overall = rate(overallCounts[i])
            if overall >= 0 && overall < 0.8 { incidentCount += 1 }
            result.append(BucketRates(
                overall:  overall,
                wifi:     rate(wifiCounts[i]),
                router:   rate(routerCounts[i]),
                internet: rate(internetCounts[i]),
                dns:      rate(dnsCounts[i]),
                web:      rate(webCounts[i])
            ))
        }
        return (result, incidentCount)
    }

    func parseStatus() -> CurrentStatus {
        guard let text = try? String(contentsOf: statusFile, encoding: .utf8) else {
            return CurrentStatus()
        }
        var s = CurrentStatus()
        for line in text.components(separatedBy: .newlines) {
            let parts = line.components(separatedBy: "=")
            guard parts.count >= 2 else { continue }
            let key   = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts.dropFirst().joined(separator: "=")
                            .trimmingCharacters(in: .whitespaces)
            switch key {
            case "checked_at": s.checkedAt   = value
            case "state":      s.state        = value
            case "ssid":       s.ssid         = value
            case "wifi_iface": s.wifiIface    = value
            case "gateway":    s.gateway      = value
            case "gw_loss":    s.gwLoss       = Int(value) ?? 0
            case "net_loss":   s.netLoss      = Int(value) ?? 0
            case "dns_sys":    s.dnsSys       = value
            case "https":      s.httpsStatus  = value
            default: break
            }
        }
        return s
    }

    func parseLastEmail() -> String {
        guard let text = try? String(contentsOf: lastEmailFile, encoding: .utf8) else {
            return "never"
        }
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "never" }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let today = df.string(from: Date())

        if raw.hasPrefix(today) {
            let timePart = String(raw.dropFirst(today.count)).trimmingCharacters(in: .whitespaces)
            let time = timePart.hasPrefix(" ") ? String(timePart.dropFirst()) : timePart
            return "today at \(time)"
        }
        return raw
    }

    func loadEnvEmail() {
        guard let url = Bundle.main.url(forResource: ".env", withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("ALERT_EMAIL=") else { continue }
            var value = String(trimmed.dropFirst("ALERT_EMAIL=".count))
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            alertEmail = value
            return
        }
    }
}
