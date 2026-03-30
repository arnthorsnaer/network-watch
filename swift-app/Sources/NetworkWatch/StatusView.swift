import SwiftUI

struct StatusView: View {
    let status: CurrentStatus

    private func dotColor(ok: Bool, degraded: Bool = false) -> Color {
        if ok && degraded { return .yellow }
        return ok ? .green : .red
    }

    private func dot(_ ok: Bool, degraded: Bool = false) -> some View {
        Text("●")
            .foregroundColor(dotColor(ok: ok, degraded: degraded))
            .font(.system(size: 12))
    }

    var body: some View {
        if status.checkedAt.isEmpty {
            Text("Waiting for first check...")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                // Overall
                HStack(spacing: 6) {
                    dot(status.allOK)
                    Text("Overall")
                        .fontWeight(.semibold)
                    Text(status.allOK
                         ? "All systems operational"
                         : "\(status.failingCount) check\(status.failingCount == 1 ? "" : "s") failing")
                        .foregroundColor(status.allOK ? .primary : .red)
                }

                Spacer().frame(height: 4)

                // WiFi
                HStack(spacing: 6) {
                    dot(status.wifiOK)
                    Text("WiFi")
                        .frame(width: 60, alignment: .leading)
                    Text(status.wifiOK
                         ? "Connected to \"\(status.ssid)\""
                         : status.wifiIface.isEmpty ? "No adapter" : "Not connected")
                }

                // Router
                HStack(spacing: 6) {
                    dot(status.routerOK, degraded: status.routerOK && status.gwLoss >= 15)
                    Text("Router")
                        .frame(width: 60, alignment: .leading)
                    Text(status.routerOK
                         ? "Reachable — \(status.gateway) (\(status.gwLoss)% loss)"
                         : "Not reachable — \(status.gateway) (\(status.gwLoss)% loss)")
                }

                // Internet
                HStack(spacing: 6) {
                    dot(status.internetOK, degraded: status.internetOK && status.netLoss >= 15)
                    Text("Internet")
                        .frame(width: 60, alignment: .leading)
                    Text(status.internetOK
                         ? "Reachable (\(status.netLoss)% loss)"
                         : "Not reachable (\(status.netLoss)% loss)")
                }

                // DNS
                HStack(spacing: 6) {
                    dot(status.dnsOK)
                    Text("DNS")
                        .frame(width: 60, alignment: .leading)
                    Text(status.dnsOK ? "Operational" : "Failed")
                }

                // Web
                HStack(spacing: 6) {
                    dot(status.webOK)
                    Text("Web")
                        .frame(width: 60, alignment: .leading)
                    Text(status.webOK ? "Web access OK" : "Web access failed")
                }

                Spacer().frame(height: 2)

                Text("Checked at \(status.checkedAt)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .font(.system(size: 13))
        }
    }
}
