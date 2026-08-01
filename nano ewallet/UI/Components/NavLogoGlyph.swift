//
//  NavLogoGlyph.swift
//  nano ewallet
//
//  Port `ic_nav_logo.xml` — logo "nano" đơn sắc dùng cho tab Trang chủ ở navbar.
//  Nền trong suốt, 1 màu để tint theo trạng thái tab (đen khi inactive, xanh khi active).
//
//  Vector gốc bọc trong <group translateX="-88.5" translateY="-67.5"> để crop bỏ padding
//  trống — SVGPath không xử lý transform của group nên dời bằng .offset theo đúng tỉ lệ
//  scale của viewBox.
//
//  Vài path vừa có fillColor vừa có strokeColor (nét dày 40/30 làm glyph đậm lên), nên
//  mỗi path phải vẽ 2 lớp fill + stroke chồng nhau.
//

import SwiftUI

struct NavLogoGlyph: View {
    var tint: Color = .primary

    private static let viewBox = CGSize(width: 800, height: 800)
    private static let translateX: CGFloat = -88.5
    private static let translateY: CGFloat = -67.5

    private struct Piece: Identifiable {
        let id: Int
        let pathData: String
        var strokeWidth: CGFloat = 0
        var evenOdd: Bool = false
    }

    private static let pieces: [Piece] = [
        Piece(
            id: 0,
            pathData: "M125 429.527L174.5 149.027H197.5L189.543 200.745C191.46 196.822 231.885 154.64 266.5 149.027C302.49 143.191 317.736 143.026 345.5 153.027C369.007 164.997 380.071 173.666 388.5 197.527C395.872 216.248 395.962 235.926 387.5 285.527L360 429.527H337L364.5 285.527C372.33 245.37 375.419 224.045 364.5 201.027C353.732 180.568 342.68 172.522 310 167.027C272.135 165.189 255.214 173.175 227 191.597C199.231 214.857 188.085 230.239 176 271.527L146.5 429.527H125Z",
            strokeWidth: 40
        ),
        Piece(
            id: 1,
            pathData: "M125 774.527L174.5 494.027H197.5L189.543 545.745C191.46 541.822 231.885 499.64 266.5 494.027C302.49 488.191 317.736 488.026 345.5 498.027C369.007 509.997 380.071 518.666 388.5 542.527C395.872 561.248 395.962 580.926 387.5 630.527L360 774.527H337L364.5 630.527C372.33 590.37 375.419 569.045 364.5 546.027C353.732 525.568 342.68 517.522 310 512.027C272.135 510.189 255.214 518.175 227 536.597C199.231 559.857 188.085 575.239 176 616.527L146.5 774.527H125Z",
            strokeWidth: 40
        ),
        Piece(
            id: 2,
            pathData: "M701.219 423.409H723.219L773.219 144.409H749.219L736.219 213.909C720.512 172.245 703.739 156.834 658.719 144.409C605.863 134.831 578.275 140.503 531.719 164.909C486.272 197.847 473.379 222.633 458.219 267.909C450.317 321.093 452.725 345.381 472.219 376.409C491.589 403.051 504.754 413.054 531.719 423.409C571.2 432.803 591.649 431.92 626.219 423.409C666.212 407.816 684.642 394.152 710.719 361.409L701.219 423.409ZM687.219 178.409C712.985 200.3 720.284 215.757 726.719 246.909C728.548 273.548 725.922 287.732 718.219 312.409C709.346 331.379 703.064 341.433 689.719 358.409C669.898 379.539 656.491 389.519 627.719 401.409C600.84 410.777 584.778 411.487 554.719 407.909C528.727 400.093 515.854 392.708 497.219 371.909C482.509 351.949 477.773 336.592 476.719 300.409C479.136 275.95 482.637 263.073 492.219 241.409C507.483 216.108 517.657 203.302 539.719 185.909C563.746 170.176 580.184 163.478 624.219 160.909C651.723 161.771 665.393 165.859 687.219 178.409Z",
            strokeWidth: 40,
            evenOdd: true
        ),
        // "o": ellipse ngoài + lỗ trong (evenOdd)
        Piece(
            id: 3,
            pathData: "M490.63 554.45 a139.753 157.556 37.8349 1 0 220.78 171.42 a139.753 157.556 37.8349 1 0 -220.78 -171.42 Z M515.689 748.639C567.286 788.713 646.769 772.717 693.217 712.911C739.666 653.105 735.492 572.137 683.894 532.063C632.296 491.989 552.814 507.985 506.365 567.791C459.917 627.597 464.091 708.566 515.689 748.639Z",
            strokeWidth: 30,
            evenOdd: true
        ),
        Piece(id: 4, pathData: "M777.847 511.924L675.966 507L692.153 527.806L777.847 511.924Z"),
        Piece(id: 5, pathData: "M852 489H611L681 507.5L852 489Z"),
        Piece(id: 6, pathData: "M824 572H738L741.5 582L824 572Z"),
        Piece(id: 7, pathData: "M775.011 588.047L733.011 587.953L734.698 597.957L775.011 588.047Z"),
    ]

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let scale = size / Self.viewBox.width

            ZStack {
                ForEach(Self.pieces) { piece in
                    let shape = SVGPath(pathData: piece.pathData, viewBox: Self.viewBox)
                    ZStack {
                        shape.fill(tint, style: FillStyle(eoFill: piece.evenOdd))
                        if piece.strokeWidth > 0 {
                            shape.stroke(
                                tint,
                                style: StrokeStyle(
                                    lineWidth: piece.strokeWidth * scale,
                                    lineCap: .round, lineJoin: .round
                                )
                            )
                        }
                    }
                }
            }
            .frame(width: size, height: size)
            .offset(x: Self.translateX * scale, y: Self.translateY * scale)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        NavLogoGlyph(tint: .black).frame(width: 24, height: 24)
        NavLogoGlyph(tint: Color(hex: 0x00A85E)).frame(width: 48, height: 48)
    }
    .padding()
}
