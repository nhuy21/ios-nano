//
//  SVGPath.swift
//  nano ewallet
//
//  Parser SVG path data (cú pháp Android VectorDrawable `android:pathData`, cùng
//  chuẩn SVG path) sang SwiftUI `Path` — dùng để port chính xác các icon vector vẽ
//  tay từ flash-wallet/app/src/main/res/drawable/*.xml, tránh vẽ lại thủ công dễ
//  sai lệch hình dạng.
//
//  Hỗ trợ lệnh: M/m, L/l, H/h, V/v, C/c, Q/q, A/a, Z/z (đủ cho toàn bộ icon giao dịch
//  đang cần port — không icon nào dùng S/s hay T/T).
//

import SwiftUI

struct SVGPath: Shape {
    let pathData: String
    /// Kích thước viewBox gốc (viewportWidth/Height khai trong file .xml Android).
    let viewBox: CGSize

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scaleX = rect.width / viewBox.width
        let scaleY = rect.height / viewBox.height

        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + x * scaleX, y: rect.minY + y * scaleY)
        }

        var current = CGPoint.zero
        var startOfSubpath = CGPoint.zero
        /// Toạ độ logic (trước scale) — cần giữ riêng vì lệnh tương đối cộng dồn theo
        /// đơn vị viewBox gốc, không phải theo pixel đã scale.
        var currentLogical = (x: 0.0, y: 0.0)
        var startLogical = (x: 0.0, y: 0.0)

        let tokens = SVGPathTokenizer.tokenize(pathData)
        var index = 0

        func nextNumber() -> Double {
            defer { index += 1 }
            return tokens[index].numberValue ?? 0
        }

        while index < tokens.count {
            guard case .command(let raw) = tokens[index] else {
                index += 1
                continue
            }
            index += 1
            let isRelative = raw.lowercased() == raw
            let cmd = raw.uppercased()

            switch cmd {
            case "M":
                let x = nextNumber(), y = nextNumber()
                let nx = isRelative ? currentLogical.x + x : x
                let ny = isRelative ? currentLogical.y + y : y
                currentLogical = (nx, ny)
                startLogical = currentLogical
                current = point(nx, ny)
                startOfSubpath = current
                path.move(to: current)
                // Các cặp toạ độ tiếp theo sau M (không có lệnh mới) ngầm định là L.
                while index < tokens.count, tokens[index].isNumber {
                    let lx = nextNumber(), ly = nextNumber()
                    let nlx = isRelative ? currentLogical.x + lx : lx
                    let nly = isRelative ? currentLogical.y + ly : ly
                    currentLogical = (nlx, nly)
                    current = point(nlx, nly)
                    path.addLine(to: current)
                }

            case "L":
                while true {
                    let x = nextNumber(), y = nextNumber()
                    let nx = isRelative ? currentLogical.x + x : x
                    let ny = isRelative ? currentLogical.y + y : y
                    currentLogical = (nx, ny)
                    current = point(nx, ny)
                    path.addLine(to: current)
                    if index >= tokens.count || !tokens[index].isNumber { break }
                }

            case "H":
                while true {
                    let x = nextNumber()
                    let nx = isRelative ? currentLogical.x + x : x
                    currentLogical.x = nx
                    current = point(nx, currentLogical.y)
                    path.addLine(to: current)
                    if index >= tokens.count || !tokens[index].isNumber { break }
                }

            case "V":
                while true {
                    let y = nextNumber()
                    let ny = isRelative ? currentLogical.y + y : y
                    currentLogical.y = ny
                    current = point(currentLogical.x, ny)
                    path.addLine(to: current)
                    if index >= tokens.count || !tokens[index].isNumber { break }
                }

            case "C":
                while true {
                    let x1 = nextNumber(), y1 = nextNumber()
                    let x2 = nextNumber(), y2 = nextNumber()
                    let x = nextNumber(), y = nextNumber()
                    let base = currentLogical
                    let c1 = point(isRelative ? base.x + x1 : x1, isRelative ? base.y + y1 : y1)
                    let c2 = point(isRelative ? base.x + x2 : x2, isRelative ? base.y + y2 : y2)
                    let nx = isRelative ? base.x + x : x
                    let ny = isRelative ? base.y + y : y
                    currentLogical = (nx, ny)
                    current = point(nx, ny)
                    path.addCurve(to: current, control1: c1, control2: c2)
                    if index >= tokens.count || !tokens[index].isNumber { break }
                }

            case "Q":
                while true {
                    let x1 = nextNumber(), y1 = nextNumber()
                    let x = nextNumber(), y = nextNumber()
                    let base = currentLogical
                    let c1 = point(isRelative ? base.x + x1 : x1, isRelative ? base.y + y1 : y1)
                    let nx = isRelative ? base.x + x : x
                    let ny = isRelative ? base.y + y : y
                    currentLogical = (nx, ny)
                    current = point(nx, ny)
                    path.addQuadCurve(to: current, control: c1)
                    if index >= tokens.count || !tokens[index].isNumber { break }
                }

            case "A":
                while true {
                    let rx = nextNumber(), ry = nextNumber()
                    let xAxisRotation = nextNumber()
                    let largeArc = nextNumber() != 0
                    let sweep = nextNumber() != 0
                    let x = nextNumber(), y = nextNumber()
                    let base = currentLogical
                    let nx = isRelative ? base.x + x : x
                    let ny = isRelative ? base.y + y : y
                    appendArc(
                        to: &path, from: currentLogical, to: (nx, ny),
                        rx: rx, ry: ry, xAxisRotationDeg: xAxisRotation,
                        largeArc: largeArc, sweep: sweep, point: point
                    )
                    currentLogical = (nx, ny)
                    current = point(nx, ny)
                    if index >= tokens.count || !tokens[index].isNumber { break }
                }

            case "Z":
                path.closeSubpath()
                current = startOfSubpath
                currentLogical = startLogical

            default:
                break
            }
        }

        return path
    }

    /// Chuyển elliptical arc (SVG "A") sang chuỗi cubic Bézier xấp xỉ — SwiftUI Path
    /// không có API arc theo endpoint parameterization như SVG, phải tự convert.
    private func appendArc(
        to path: inout Path,
        from: (x: Double, y: Double),
        to end: (x: Double, y: Double),
        rx: Double, ry: Double,
        xAxisRotationDeg: Double,
        largeArc: Bool, sweep: Bool,
        point: (Double, Double) -> CGPoint
    ) {
        var rx = abs(rx), ry = abs(ry)
        if rx == 0 || ry == 0 {
            path.addLine(to: point(end.x, end.y))
            return
        }

        let phi = xAxisRotationDeg * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)

        let dx2 = (from.x - end.x) / 2
        let dy2 = (from.y - end.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2

        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let scale = lambda.squareRoot()
            rx *= scale
            ry *= scale
        }

        let sign: Double = (largeArc != sweep) ? 1 : -1
        let num = max(0, rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p)
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coef = den == 0 ? 0 : sign * (num / den).squareRoot()
        let cxp = coef * (rx * y1p / ry)
        let cyp = coef * -(ry * x1p / rx)

        let cx = cosPhi * cxp - sinPhi * cyp + (from.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (from.y + end.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let dot = ux * vx + uy * vy
            let len = (ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot()
            var a = acos(min(1, max(-1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }

        let ux = (x1p - cxp) / rx, uy = (y1p - cyp) / ry
        let vx = (-x1p - cxp) / rx, vy = (-y1p - cyp) / ry
        var theta1 = angle(1, 0, ux, uy)
        var deltaTheta = angle(ux, uy, vx, vy)

        if !sweep && deltaTheta > 0 { deltaTheta -= 2 * .pi }
        if sweep && deltaTheta < 0 { deltaTheta += 2 * .pi }

        // Chia cung thành tối đa các đoạn 90° rồi xấp xỉ mỗi đoạn bằng 1 cubic Bézier —
        // đủ chính xác cho icon nhỏ (không cần chuẩn arc toán học tuyệt đối).
        let segments = max(1, Int(ceil(abs(deltaTheta) / (.pi / 2))))
        let delta = deltaTheta / Double(segments)

        for _ in 0..<segments {
            let theta2 = theta1 + delta
            let t = 4.0 / 3.0 * tan(delta / 4)

            let cosT1 = cos(theta1), sinT1 = sin(theta1)
            let cosT2 = cos(theta2), sinT2 = sin(theta2)

            let start = ellipsePoint(cx: cx, cy: cy, rx: rx, ry: ry, cosPhi: cosPhi, sinPhi: sinPhi, theta: theta1)
            let endPt = ellipsePoint(cx: cx, cy: cy, rx: rx, ry: ry, cosPhi: cosPhi, sinPhi: sinPhi, theta: theta2)

            let d1x = -rx * cosPhi * sinT1 - ry * sinPhi * cosT1
            let d1y = -rx * sinPhi * sinT1 + ry * cosPhi * cosT1
            let d2x = -rx * cosPhi * sinT2 - ry * sinPhi * cosT2
            let d2y = -rx * sinPhi * sinT2 + ry * cosPhi * cosT2

            let c1 = (x: start.x + t * d1x, y: start.y + t * d1y)
            let c2 = (x: endPt.x - t * d2x, y: endPt.y - t * d2y)

            path.addCurve(
                to: point(endPt.x, endPt.y),
                control1: point(c1.x, c1.y),
                control2: point(c2.x, c2.y)
            )
            theta1 = theta2
        }
    }

    private func ellipsePoint(
        cx: Double, cy: Double, rx: Double, ry: Double, cosPhi: Double, sinPhi: Double, theta: Double
    ) -> (x: Double, y: Double) {
        let cosT = cos(theta), sinT = sin(theta)
        let x = cx + rx * cosPhi * cosT - ry * sinPhi * sinT
        let y = cy + rx * sinPhi * cosT + ry * cosPhi * sinT
        return (x, y)
    }
}

/// Token hoá pathData: tách lệnh (chữ cái) và số (hỗ trợ số âm, thập phân, số dính
/// liền nhau kiểu Android "1.5.5" = "1.5" + ".5").
///
/// Lệnh `A`/`a` (elliptical arc) có 2 tham số flag (large-arc, sweep) LUÔN đúng 1 chữ số
/// (0 hoặc 1), và SVG cho phép viết dính liền số toạ độ theo sau (vd "...0110,5..." =
/// flag=0, flag=1, x=10, y=5). Tokenizer phải biết đang ở tham số thứ mấy của lệnh A để
/// đọc đúng 1 ký tự cho 2 flag đó, không được gộp chung với số phía sau.
private enum SVGPathTokenizer {
    static func tokenize(_ data: String) -> [SVGToken] {
        var tokens: [SVGToken] = []
        let chars = Array(data)
        var i = 0
        /// Số tham số còn lại của lệnh A/a hiện tại cần đọc theo cú pháp đặc biệt
        /// (7 tham số: rx, ry, x-rotation, large-arc-flag, sweep-flag, x, y).
        var argsRemainingForArc = 0

        func isCommandChar(_ c: Character) -> Bool {
            "MmLlHhVvCcSsQqTtAaZz".contains(c)
        }

        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace || c == "," {
                i += 1
                continue
            }
            if isCommandChar(c) {
                tokens.append(.command(String(c)))
                argsRemainingForArc = (c == "A" || c == "a") ? 7 : 0
                i += 1
                continue
            }

            // Vị trí flag (tham số thứ 4, thứ 5 trong nhóm 7 của lệnh A) — chỉ đọc
            // đúng 1 ký tự số, không gộp với ký tự theo sau.
            let isFlagPosition = argsRemainingForArc == 3 || argsRemainingForArc == 2
            if isFlagPosition, c == "0" || c == "1" {
                tokens.append(.number(c == "1" ? 1 : 0))
                argsRemainingForArc -= 1
                i += 1
                continue
            }

            // Đọc 1 số: [-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?
            var numStr = ""
            if c == "-" || c == "+" {
                numStr.append(c)
                i += 1
            }
            var sawDot = false
            while i < chars.count {
                let ch = chars[i]
                if ch.isNumber {
                    numStr.append(ch)
                    i += 1
                } else if ch == "." && !sawDot {
                    sawDot = true
                    numStr.append(ch)
                    i += 1
                } else {
                    break
                }
            }
            if !numStr.isEmpty, numStr != "-", numStr != "+" {
                tokens.append(.number(Double(numStr) ?? 0))
                if argsRemainingForArc > 0 { argsRemainingForArc -= 1 }
            } else {
                i += 1
            }
        }
        return tokens
    }
}

private enum SVGToken {
    case command(String)
    case number(Double)

    var isNumber: Bool {
        if case .number = self { return true }
        return false
    }

    var numberValue: Double? {
        if case .number(let v) = self { return v }
        return nil
    }
}
