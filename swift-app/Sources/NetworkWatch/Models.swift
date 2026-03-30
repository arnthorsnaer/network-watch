import Foundation

enum DisplayMode: CaseIterable {
    case minute, hour, day

    var numBuckets: Int {
        switch self {
        case .minute: return 60
        case .hour:   return 24
        case .day:    return 30
        }
    }

    var bucketSeconds: Double {
        switch self {
        case .minute: return 60
        case .hour:   return 3600
        case .day:    return 86400
        }
    }

    var windowSeconds: Double {
        Double(numBuckets) * bucketSeconds
    }

    var leftLabel: String {
        switch self {
        case .minute: return "60m ago"
        case .hour:   return "24h ago"
        case .day:    return "30d ago"
        }
    }

    var tabLabel: String {
        switch self {
        case .minute: return "minute"
        case .hour:   return "hour"
        case .day:    return "day"
        }
    }
}

struct CheckRow {
    let epoch: Double
    let wifi: Bool
    let router: Bool
    let internet: Bool
    let dns: Bool
    let web: Bool

    var allOK: Bool { wifi && router && internet && dns && web }
}

struct BucketRates {
    let overall: Double
    let wifi: Double
    let router: Double
    let internet: Double
    let dns: Double
    let web: Double

    static let noData = BucketRates(
        overall: -1, wifi: -1, router: -1,
        internet: -1, dns: -1, web: -1
    )
}

struct CurrentStatus {
    var checkedAt: String = ""
    var state: String = ""
    var ssid: String = ""
    var wifiIface: String = ""
    var gateway: String = ""
    var gwLoss: Int = 0
    var netLoss: Int = 0
    var httpsStatus: String = ""
    var dnsSys: String = ""

    var wifiOK: Bool    { !ssid.isEmpty }
    var routerOK: Bool  { gwLoss < 20 }
    var internetOK: Bool { netLoss < 20 }
    var dnsOK: Bool     { !dnsSys.isEmpty }
    var webOK: Bool     { ["200", "301", "302"].contains(httpsStatus) }
    var allOK: Bool     { wifiOK && routerOK && internetOK && dnsOK && webOK }

    var failingCount: Int {
        [wifiOK, routerOK, internetOK, dnsOK, webOK].filter { !$0 }.count
    }
}
