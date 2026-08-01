//
//  WhiteTopShape.swift
//  nano ewallet
//
//  Port `WhiteTopShape` trong HomeScreen.kt.
//
//  Nền trắng phía dưới của Home: đỉnh bo cong LÕM — 2 mép ở đỉnh, phần giữa võng
//  xuống nhẹ — rồi chồng lên đáy dải CTA nạp tiền.
//

import SwiftUI

struct WhiteTopShape: Shape {
    /// Tỉ lệ độ võng so với bề rộng (Kotlin dùng 0.03, điểm điều khiển nhân đôi).
    var curveRatio: CGFloat = 0.03

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let curve = w * curveRatio

        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: w, y: 0),
            control: CGPoint(x: w / 2, y: curve * 2)
        )
        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.closeSubpath()
        return path
    }
}
