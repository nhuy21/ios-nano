//
//  AnimatedQrScanIcon.swift
//  nano ewallet
//
//  Port `AnimatedQrScanIcon` trong MainScreen.kt — icon quét QR động ở nút FAB navbar.
//
//  Cấu trúc theo icon QR gốc: 4 ô vuông ngoài (kiểu finder-pattern) ở 4 góc, mỗi ô có 1
//  chấm vuông nhỏ cố định bên trong. CHỈ ô vuông NGOÀI tự to/nhỏ theo thời gian (lệch
//  pha nhau) — chấm bên trong luôn giữ nguyên kích thước. Luôn có 1 thanh ngang quét
//  lên/xuống; phần thanh quét ĐÃ đi qua trong lượt hiện tại mờ dần đi.
//

import SwiftUI

struct AnimatedQrScanIcon: View {
    var color: Color = .white

    // Chu kỳ (giây) — mirror tween() bên Kotlin.
    private static let scanPeriod: Double = 1.5      // 1 lượt quét
    private static let legPeriod: Double = 3.0       // 2 lượt (xuống + lên)

    private static let dimAlpha: Double = 0.25
    private static let fadeBand: Double = 0.18

    /// (chu kỳ, độ trễ) của 4 ô — lệch pha cho tự nhiên.
    private static let pulseSpecs: [(period: Double, delay: Double)] = [
        (1.0, 0), (1.1, 0.15), (0.95, 0.30), (1.05, 0.45),
    ]

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                draw(ctx: &ctx, size: size, time: t)
            }
        }
    }

    // MARK: - Nhịp

    /// Sóng tam giác 0→1→0 (mirror RepeatMode.Reverse).
    private func triangle(_ time: Double, period: Double, delay: Double = 0) -> Double {
        let phase = ((time - delay).truncatingRemainder(dividingBy: period * 2) + period * 2)
            .truncatingRemainder(dividingBy: period * 2)
        return phase <= period ? phase / period : 2 - phase / period
    }

    /// Xấp xỉ FastOutSlowInEasing bằng smoothstep.
    private func easeInOut(_ x: Double) -> Double {
        x * x * (3 - 2 * x)
    }

    // MARK: - Vẽ

    private func draw(ctx: inout GraphicsContext, size: CGSize, time: Double) {
        let u = min(size.width, size.height) / 24
        let squareGap = 1.25 * u
        let squareSize = 12 * u - squareGap / 2
        let radius = 2.3 * u
        let strokeWidth = 1.6 * u
        let dotSize = 3.1 * u
        let gapExtra = 1.3 * u
        let dashGapLen = 1.6 * u

        // Thanh quét: 0→1→0 tuyến tính; legPhase 0→2 chạy thẳng để biết đang quét
        // xuống (0..1) hay lên (1..2).
        let scanT = triangle(time, period: Self.scanPeriod)
        let legPhase = (time.truncatingRemainder(dividingBy: Self.legPeriod) + Self.legPeriod)
            .truncatingRemainder(dividingBy: Self.legPeriod) / Self.scanPeriod
        let scanningDown = legPhase < 1
        let withinLeg = scanningDown ? legPhase : legPhase - 1

        func sweptAlpha(_ yNorm: Double) -> Double {
            let swept = scanningDown ? yNorm : 1 - yNorm
            let d = withinLeg - swept
            if d <= 0 { return 1 }
            if d >= Self.fadeBand { return Self.dimAlpha }
            return 1 + (Self.dimAlpha - 1) * (d / Self.fadeBand)
        }

        let topRowAlpha = sweptAlpha(Double((squareSize / 2) / size.height))
        let bottomRowAlpha = sweptAlpha(Double((size.height - squareSize / 2) / size.height))

        let pulses = Self.pulseSpecs.map { spec in
            0.8 + 0.2 * easeInOut(triangle(time, period: spec.period, delay: spec.delay))
        }

        /// 1 đoạn thẳng, có thể chẻ đôi để tạo nét đứt giữa cạnh.
        func edgePath(_ p1: CGPoint, _ p2: CGPoint, dashed: Bool) -> Path {
            var path = Path()
            guard dashed else {
                path.move(to: p1)
                path.addLine(to: p2)
                return path
            }
            let halfGap = dashGapLen / 2
            if p1.y == p2.y {
                let midX = (p1.x + p2.x) / 2
                let dir: CGFloat = p2.x > p1.x ? 1 : -1
                path.move(to: p1)
                path.addLine(to: CGPoint(x: midX - dir * halfGap, y: p1.y))
                path.move(to: CGPoint(x: midX + dir * halfGap, y: p1.y))
                path.addLine(to: p2)
            } else {
                let midY = (p1.y + p2.y) / 2
                let dir: CGFloat = p2.y > p1.y ? 1 : -1
                path.move(to: p1)
                path.addLine(to: CGPoint(x: p1.x, y: midY - dir * halfGap))
                path.move(to: CGPoint(x: p1.x, y: midY + dir * halfGap))
                path.addLine(to: p2)
            }
            return path
        }

        /// Viền ô vuông có thể hở ở vài góc và/hoặc đứt giữa cạnh.
        func borderWithGaps(left: CGFloat, top: CGFloat, openCorners: Set<Int>, dashEdges: Set<Int>) -> Path {
            let right = left + squareSize
            let bottom = top + squareSize
            func off(_ corner: Int) -> CGFloat { openCorners.contains(corner) ? radius + gapExtra : radius }

            var path = Path()
            path.addPath(edgePath(CGPoint(x: left + off(0), y: top), CGPoint(x: right - off(1), y: top), dashed: dashEdges.contains(0)))
            path.addPath(edgePath(CGPoint(x: right, y: top + off(1)), CGPoint(x: right, y: bottom - off(2)), dashed: dashEdges.contains(1)))
            path.addPath(edgePath(CGPoint(x: right - off(2), y: bottom), CGPoint(x: left + off(3), y: bottom), dashed: dashEdges.contains(2)))
            path.addPath(edgePath(CGPoint(x: left, y: bottom - off(3)), CGPoint(x: left, y: top + off(0)), dashed: dashEdges.contains(3)))

            // index góc: 0=trên-trái, 1=trên-phải, 2=dưới-phải, 3=dưới-trái
            let corners: [(Int, CGFloat, CGFloat, Double)] = [
                (0, left + radius, top + radius, 180),
                (1, right - radius, top + radius, 270),
                (2, right - radius, bottom - radius, 0),
                (3, left + radius, bottom - radius, 90),
            ]
            for (index, cx, cy, start) in corners where !openCorners.contains(index) {
                path.move(to: CGPoint(
                    x: cx + radius * cos(start * .pi / 180),
                    y: cy + radius * sin(start * .pi / 180)
                ))
                path.addArc(
                    center: CGPoint(x: cx, y: cy), radius: radius,
                    startAngle: .degrees(start), endAngle: .degrees(start + 90), clockwise: false
                )
            }
            return path
        }

        func squareWithFixedDot(
            left: CGFloat, top: CGFloat, pulse: Double, alpha: Double,
            openCorners: Set<Int> = [], dashEdges: Set<Int> = [], dotOverride: CGFloat? = nil
        ) {
            let cx = left + squareSize / 2
            let cy = top + squareSize / 2
            let shade = color.opacity(alpha)

            // Ô vuông ngoài — phóng to/nhỏ quanh tâm chính nó (kể cả độ dày nét).
            ctx.drawLayer { layer in
                layer.translateBy(x: cx, y: cy)
                layer.scaleBy(x: pulse, y: pulse)
                layer.translateBy(x: -cx, y: -cy)

                let outline: Path = (openCorners.isEmpty && dashEdges.isEmpty)
                    ? Path(roundedRect: CGRect(x: left, y: top, width: squareSize, height: squareSize),
                           cornerRadius: radius)
                    : borderWithGaps(left: left, top: top, openCorners: openCorners, dashEdges: dashEdges)

                layer.stroke(
                    outline, with: .color(shade),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
                )
            }

            // Chấm bên trong — vẽ ngoài layer scale nên luôn giữ nguyên kích thước.
            let dot = dotOverride ?? dotSize
            ctx.fill(
                Path(roundedRect: CGRect(x: cx - dot / 2, y: cy - dot / 2, width: dot, height: dot),
                     cornerRadius: dot * 0.32),
                with: .color(shade)
            )
        }

        squareWithFixedDot(left: 0, top: 0, pulse: pulses[0], alpha: topRowAlpha)
        squareWithFixedDot(left: size.width - squareSize, top: 0, pulse: pulses[1], alpha: topRowAlpha)
        squareWithFixedDot(left: 0, top: size.height - squareSize, pulse: pulses[2], alpha: bottomRowAlpha)
        // Ô thứ 4: hở 2 góc (trên-phải + dưới-trái), đứt giữa cạnh trên + trái, chấm to hơn.
        squareWithFixedDot(
            left: size.width - squareSize, top: size.height - squareSize,
            pulse: pulses[3], alpha: bottomRowAlpha,
            openCorners: [1, 3], dashEdges: [0, 3], dotOverride: dotSize * 1.35
        )

        // Thanh quét ngang — chạy trong khoảng hở giữa các ô vuông.
        let scanTop = squareSize * 0.18
        let scanBottom = size.height - squareSize * 0.18
        let scanY = scanTop + (scanBottom - scanTop) * CGFloat(scanT)
        let barHeight = 1.6 * u
        let barRect = CGRect(
            x: squareSize * 0.15, y: scanY - barHeight / 2,
            width: size.width - squareSize * 0.3, height: barHeight
        )
        ctx.fill(
            Path(roundedRect: barRect, cornerRadius: barHeight / 2),
            with: .linearGradient(
                Gradient(colors: [color.opacity(0), color.opacity(0.9), color.opacity(0)]),
                startPoint: CGPoint(x: barRect.minX, y: barRect.midY),
                endPoint: CGPoint(x: barRect.maxX, y: barRect.midY)
            )
        )
    }
}

#Preview {
    ZStack {
        Color(hex: 0x00A24A)
        AnimatedQrScanIcon().frame(width: 28, height: 28)
    }
    .frame(width: 80, height: 80)
}
