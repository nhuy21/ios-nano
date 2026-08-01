//
//  DomeTopShape.swift
//  nano ewallet
//
//  Port `DomeTopShape` trong MainScreen.kt.
//
//  Mép trên PHẲNG như pill thường, nhưng nhô lên 1 gò tròn êm ở chính giữa (quanh nút
//  QR), nối vào phần phẳng bằng 2 đoạn cubic Bezier liên tục — bar "ôm" lấy nút QR
//  thành 1 khối liền mạch kiểu VNPAY, thay vì nút nổi rời trên mép bar.
//

import SwiftUI

struct DomeTopShape: Shape {
    /// Bán kính bo 4 góc.
    var corner: CGFloat
    /// Y của mép trên phẳng (phần ngoài gò), tính từ đỉnh khung.
    var flatTopY: CGFloat
    /// Nửa bề rộng chân gò.
    var bumpHalfWidth: CGFloat
    /// Y đỉnh gò — nhỏ hơn `flatTopY` vì trục y tăng xuống dưới.
    var bumpPeakY: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let flatRegionH = h - flatTopY
        let r = min(corner, flatRegionH / 2, w / 2)
        let halfW = min(max(bumpHalfWidth, 0), w / 2 - r)
        let centerX = w / 2
        let notchLeft = min(max(centerX - halfW, r), w - r)
        let notchRight = min(max(centerX + halfW, r), w - r)

        var path = Path()
        path.move(to: CGPoint(x: r, y: flatTopY))
        path.addLine(to: CGPoint(x: notchLeft, y: flatTopY))

        // Gò tròn: 2 cubic nối liên tục qua đỉnh, không có đoạn phẳng ở giữa.
        path.addCurve(
            to: CGPoint(x: centerX, y: bumpPeakY),
            control1: CGPoint(x: notchLeft + halfW * 0.55, y: flatTopY),
            control2: CGPoint(x: centerX - halfW * 0.55, y: bumpPeakY)
        )
        path.addCurve(
            to: CGPoint(x: notchRight, y: flatTopY),
            control1: CGPoint(x: centerX + halfW * 0.55, y: bumpPeakY),
            control2: CGPoint(x: notchRight - halfW * 0.55, y: flatTopY)
        )

        path.addLine(to: CGPoint(x: w - r, y: flatTopY))
        path.addArc(
            center: CGPoint(x: w - r, y: flatTopY + r), radius: r,
            startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false
        )
        path.addLine(to: CGPoint(x: w, y: h - r))
        path.addArc(
            center: CGPoint(x: w - r, y: h - r), radius: r,
            startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
        )
        path.addLine(to: CGPoint(x: r, y: h))
        path.addArc(
            center: CGPoint(x: r, y: h - r), radius: r,
            startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
        )
        path.addLine(to: CGPoint(x: 0, y: flatTopY + r))
        path.addArc(
            center: CGPoint(x: r, y: flatTopY + r), radius: r,
            startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
