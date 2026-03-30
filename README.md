# Network Watch

Continuous network monitoring for macOS. Tracks WiFi, router, internet, DNS, and web connectivity with a live heatmap UI. Sends email alerts when connectivity is restored after an outage.

Available as both a terminal UI and a native macOS app.

## Architecture

- **`network-watchd`** — daemon that runs checks every 30 seconds, writes status and CSV data to `~/Library/Application Support/NetworkWatch/`
- **`network-watch.sh`** — terminal UI: starts the daemon if needed, shows a live ANSI heatmap
- **`swift-app/`** — native macOS SwiftUI app that reads the same data files
- **`build.sh`** — builds `NetworkWatch.app` from the Swift source

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

First-time install on a new Mac: right-click → Open (required to bypass Gatekeeper for unsigned apps).

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
- **Incident summary** — sent when all checks recover after an outage
- **Log email** — on demand via `l` key (CLI) or Send Log button (app)

## Data Files

| File | Description |
|------|-------------|
| `~/Library/Application Support/NetworkWatch/checks.csv` | Raw check history (epoch, 5 boolean columns) |
| `~/Library/Application Support/NetworkWatch/status` | Latest check result (key=value) |
| `~/Library/Logs/NetworkWatch/network-watch.log` | Human-readable log |
