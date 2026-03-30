import Foundation

class DaemonManager: ObservableObject {
    @Published var isRunning = false
    private var process: Process?

    func startIfNeeded() {
        guard !isRunning else { return }

        guard let daemonURL = Bundle.main.url(forResource: "network-watchd", withExtension: nil) else {
            return
        }
        let daemonPath = daemonURL.path

        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: daemonPath) {
            let perms = attrs[.posixPermissions] as? Int ?? 0
            if perms & 0o111 == 0 {
                try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: daemonPath)
            }
        } else {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: daemonPath)
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [daemonPath]
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice

        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRunning = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self?.startIfNeeded()
            }
        }

        do {
            try p.run()
            process = p
            DispatchQueue.main.async { self.isRunning = true }
        } catch {
            // silently fail; terminationHandler won't fire so no restart loop
        }
    }

    func sendLog(completion: @escaping () -> Void) {
        guard let daemonURL = Bundle.main.url(forResource: "network-watchd", withExtension: nil) else {
            completion(); return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [daemonURL.path, "--send-log"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice
        p.terminationHandler = { _ in completion() }
        try? p.run()
    }

    func stop() {
        process?.terminate()
        process = nil
    }
}
