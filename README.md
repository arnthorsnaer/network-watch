# Network Watch

A macOS tool for diagnosing intermittent network problems that are hard to catch because they only happen occasionally, briefly, or when no one is paying attention.

<img width="1012" height="632" alt="Screenshot 2026-03-30 at 08 07 57" src="https://github.com/user-attachments/assets/c1aabd32-a745-4950-a7d5-ede83602bf2b" />

<img width="912" height="744" alt="Screenshot 2026-03-30 at 08 43 45" src="https://github.com/user-attachments/assets/7238a57d-dab5-4e52-9204-7fb43eb470af" />

## The Problem It Solves

Intermittent connectivity issues are frustrating to diagnose. The connection drops for 30 seconds, then comes back. By the time you open a browser or call your ISP, everything looks fine. You can't prove anything happened, and you can't tell whether the problem is the WiFi, the router, the ISP, or something else.

Network Watch runs silently in the background and checks every 30 seconds, building up a history of exactly what failed and when. The next time someone says "the internet was down this morning," you can open the app and see precisely what happened — whether WiFi dropped, the router was unreachable, or the ISP connection went down — down to the minute.

## Who It's For

Network Watch is designed to be installed on a non-technical person's Mac and left running. They don't need to interact with it. If email is configured, they'll automatically receive a summary when an outage resolves. A more technical person can check in remotely, ask for the log, or look at the heatmap to understand patterns over time.

## What It Shows

The main view is a colour-coded heatmap covering the last 60 minutes, 24 hours, or 30 days. Green means everything was working; red means something failed. Below the heatmap is a current status panel showing each check individually:

- **WiFi** — is the Mac connected to a wireless network?
- **Router** — can it reach the local gateway (the box in the house)?
- **Internet** — can it reach external IP addresses (8.8.8.8, 1.1.1.1)?
- **DNS** — can it resolve domain names?
- **Web** — can it complete an HTTPS request to google.com?

This layered approach pinpoints where the problem is. If Router fails but Internet doesn't, the issue is local. If WiFi is fine but Internet fails, the ISP is the likely culprit. If DNS fails alone, it's a resolver issue.

---

## Architecture

- **`network-watchd`** — daemon that runs checks every 30 seconds, writes status and CSV data to `~/Library/Application Support/NetworkWatch/`
- **`network-watch.sh`** — terminal UI: starts the daemon, shows a live ANSI heatmap. The daemon stops when the CLI exits.
- **`swift-app/`** — native macOS SwiftUI app that reads the same data files. The daemon starts when the app opens and stops when the app quits.
- **`build.sh`** — builds `NetworkWatch.app` from the Swift source

The daemon only runs while the app or CLI is open — monitoring is intentionally tied to the application lifetime. Gaps in the heatmap where nothing was checked are shown in grey.

## Setup

```bash
cp .env.sample .env
# Edit .env with your email credentials (optional — monitoring works without email)
```

## Running the CLI

```bash
./network-watch.sh
```

Keys: `m` minute · `h` hour · `d` day · `l` send log by email

## Building the macOS App

Requires Swift toolchain (available via Xcode command-line tools).

```bash
./build.sh --release
```

This produces `NetworkWatch.app`. Distribute by zipping it:

```bash
zip -r NetworkWatch.zip NetworkWatch.app
```

First-time install on a new Mac: right-click → Open (required to bypass Gatekeeper for unsigned apps). After that, add it to Login Items so it starts automatically.

## What It Monitors

| Check    | Method |
|----------|--------|
| WiFi     | `networksetup` + `ipconfig getsummary` |
| Router   | ping to default gateway |
| Internet | ping to 8.8.8.8 and 1.1.1.1 |
| DNS      | `dig google.com` via system resolver |
| Web      | HTTPS request to google.com |

## Email Alerts

Requires a Gmail account with an App Password. Set `ALERT_EMAIL`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_FROM`, and `SMTP_URL` in `.env`.

- **Startup email** — sent when the daemon starts, includes current status
- **Incident summary** — sent when all checks recover after an outage, with a 24-hour summary
- **Log email** — on demand via `l` key (CLI) or Send Log button (app)

Email is intentionally sent *after* recovery rather than at the moment of failure — during an outage the network is unavailable, so the email would never reach its destination anyway.

## Data Files

| File | Description |
|------|-------------|
| `~/Library/Application Support/NetworkWatch/checks.csv` | Raw check history (epoch, 5 boolean columns) |
| `~/Library/Application Support/NetworkWatch/status` | Latest check result (key=value) |
| `~/Library/Logs/NetworkWatch/network-watch.log` | Human-readable log |
