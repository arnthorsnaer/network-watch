import SwiftUI

struct HeatmapView: View {
    let buckets: [BucketRates]
    let mode: DisplayMode

    private var cellWidth: CGFloat  { mode == .minute ? 8 : 14 }
    private let cellHeight: CGFloat = 16
    private let labelWidth: CGFloat = 75

    private let rowLabels = ["Overall", "WiFi", "Router", "Internet", "DNS", "Web"]

    private func color(for rate: Double) -> Color {
        if rate < 0 {
            return Color(red: 48/255, green: 54/255, blue: 61/255)
        } else if rate >= 0.5 {
            let t = (rate - 0.5) * 2
            return Color(
                red:   (214 - 157 * t) / 255,
                green: (168 +  43 * t) / 255,
                blue:  ( 83 *       t) / 255
            )
        } else {
            let t = rate * 2
            return Color(
                red:   (218 -   4 * t) / 255,
                green: ( 54 + 114 * t) / 255,
                blue:  ( 51 -  51 * t) / 255
            )
        }
    }

    private func rateForRow(_ row: Int, bucket: BucketRates) -> Double {
        switch row {
        case 0: return bucket.overall
        case 1: return bucket.wifi
        case 2: return bucket.router
        case 3: return bucket.internet
        case 4: return bucket.dns
        case 5: return bucket.web
        default: return -1
        }
    }

    // Column header label positions
    private var labelPositions: [(Int, String)] {
        var pairs: [(Int, String)] = []
        let n = buckets.count
        let now = Date()

        switch mode {
        case .minute:
            let cal = Calendar.current
            let positions = [0, 15, 30, 45]
            for pos in positions {
                let date = Date(timeIntervalSinceNow: -Double(n - pos) * mode.bucketSeconds)
                let comps = cal.dateComponents([.hour, .minute], from: date)
                let h = comps.hour ?? 0
                let m = comps.minute ?? 0
                pairs.append((pos, String(format: "%02d:%02d", h, m)))
            }
        case .hour:
            let cal = Calendar.current
            let every = 4
            for i in stride(from: 0, to: n, by: every) {
                let date = Date(timeIntervalSince1970: now.timeIntervalSince1970 - Double(n - i) * mode.bucketSeconds)
                let h = cal.component(.hour, from: date)
                pairs.append((i, String(format: "%02d", h)))
            }
        case .day:
            let cal = Calendar.current
            let every = 7
            for i in stride(from: 0, to: n, by: every) {
                let date = Date(timeIntervalSince1970: now.timeIntervalSince1970 - Double(n - i) * mode.bucketSeconds)
                let d = cal.component(.day, from: date)
                pairs.append((i, String(d)))
            }
        }
        return pairs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 0) {
                    Text(rowLabels[row])
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: labelWidth, alignment: .leading)
                        .foregroundColor(.secondary)

                    ForEach(0..<buckets.count, id: \.self) { col in
                        Rectangle()
                            .fill(color(for: rateForRow(row, bucket: buckets[col])))
                            .frame(width: cellWidth, height: cellHeight)
                    }
                }

                if row == 0 {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)
                        .padding(.leading, labelWidth)
                }
            }

            // Axis labels
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    Spacer().frame(width: labelWidth)
                    GeometryReader { geo in
                        ZStack(alignment: .topLeading) {
                            ForEach(labelPositions, id: \.0) { (idx, label) in
                                Text(label)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .offset(x: CGFloat(idx) * cellWidth, y: 0)
                            }
                            // "now" label at the end
                            Text("now")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .offset(x: max(0, CGFloat(buckets.count - 1) * cellWidth - 12), y: 0)
                        }
                    }
                    .frame(height: 14)
                }

                // Left label
                HStack(spacing: 0) {
                    Text(mode.leftLabel)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: labelWidth, alignment: .leading)
                    Spacer()
                }
            }
            .padding(.top, 2)
        }
    }
}
