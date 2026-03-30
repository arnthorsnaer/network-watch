import SwiftUI

struct ContentView: View {
    @StateObject var store  = DataStore()
    @StateObject var daemon = DaemonManager()
    @State private var mode: DisplayMode = .minute
    @State private var now: Date = Date()
    @State private var logSendState: LogSendState = .idle

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var machineName: String {
        Host.current().localizedName ?? "This Mac"
    }

    private var versionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(v) (\(b))"
    }

    private var modeIndex: Int {
        DisplayMode.allCases.firstIndex(of: mode) ?? 0
    }

    enum LogSendState { case idle, sending, done }

    private static let checkedAtFormatter: DateFormatter = {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm:ss"; return df
    }()

    private func secondsUntilNextCheck() -> Int? {
        guard !store.status.checkedAt.isEmpty,
              let checkedAt = Self.checkedAtFormatter.date(from: store.status.checkedAt)
        else { return nil }
        let secs = Int(checkedAt.addingTimeInterval(30).timeIntervalSince(now))
        return max(0, secs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Title row
            HStack {
                Text("Network Watch — \(machineName)")
                    .font(.headline)
                Text(versionString)
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Text(now, format: .dateTime.day().month(.wide).year())
                    .font(.caption).foregroundColor(.secondary)
                Text(now, style: .time)
                    .font(.caption).foregroundColor(.secondary)
            }

            // Mode picker — native segmented control
            HStack {
                Picker("Mode", selection: $mode) {
                    ForEach(DisplayMode.allCases, id: \.self) { m in
                        Text(m.tabLabel.capitalized).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()

                Spacer()

                // Send Log button (only when email is configured)
                if !store.alertEmail.isEmpty {
                    Button(action: sendLog) {
                        switch logSendState {
                        case .idle:    Label("Send Log", systemImage: "envelope")
                        case .sending: Label("Sending…",  systemImage: "paperplane")
                        case .done:    Label("Sent",       systemImage: "checkmark")
                        }
                    }
                    .disabled(logSendState == .sending)
                    .controlSize(.small)
                }
            }

            Text("── Current Status ──────────────────────")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)

            StatusView(status: store.status)

            Divider()

            // Heatmap
            if !store.buckets.isEmpty {
                HeatmapView(buckets: store.buckets[modeIndex], mode: mode)
            }

            // Incidents + email row
            HStack {
                let inc = store.incidents.indices.contains(modeIndex) ? store.incidents[modeIndex] : 0
                Text(inc == 0 ? "No incidents in this window"
                     : inc == 1 ? "1 incident in this window"
                     : "\(inc) incidents in this window")
                    .font(.caption)
                    .foregroundColor(inc > 0 ? .red : .secondary)
                Spacer()
                if !store.alertEmail.isEmpty {
                    Text("Email: \(store.alertEmail)  ·  last sent: \(store.lastEmailSent)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Daemon status + countdown
            HStack(spacing: 6) {
                Circle()
                    .fill(daemon.isRunning ? Color.green : Color.yellow)
                    .frame(width: 8, height: 8)
                Text(daemon.isRunning ? "Monitoring" : "Starting…")
                    .font(.caption).foregroundColor(.secondary)
                if let secs = secondsUntilNextCheck() {
                    Text("· next check in \(secs)s")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 700)
        .onAppear { daemon.startIfNeeded() }
        .onReceive(clock) { t in now = t }
        // Keep keyboard shortcuts working
        .background(
            Group {
                Button("") { mode = .minute }.keyboardShortcut("m", modifiers: []).opacity(0)
                Button("") { mode = .hour   }.keyboardShortcut("h", modifiers: []).opacity(0)
                Button("") { mode = .day    }.keyboardShortcut("d", modifiers: []).opacity(0)
            }
        )
    }

    private func sendLog() {
        logSendState = .sending
        daemon.sendLog {
            DispatchQueue.main.async {
                logSendState = .done
                store.refresh()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    logSendState = .idle
                }
            }
        }
    }
}
