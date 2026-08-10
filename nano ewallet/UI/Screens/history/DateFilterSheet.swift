//
//  DateFilterSheet.swift
//  nano ewallet
//
//  Mirror DateFilterDialog trong HistoryScreen.kt — 5 preset + chọn khoảng ngày
//  tuỳ chỉnh qua DatePicker (thay Material3 DateRangePicker của Android).
//

import SwiftUI

struct DateFilterSheet: View {
    @Binding var dateStart: Date?
    @Binding var dateEnd: Date?
    let onApply: () -> Void
    let onDismiss: () -> Void

    @State private var customStart: Date = Date()
    @State private var customEnd: Date = Date()

    private var presets: [(label: String, start: Date?, end: Date?)] {
        let today = Calendar.app.startOfDay(for: Date())
        return [
            ("Tất cả", nil, nil),
            ("Hôm nay", today, today),
            ("Hôm qua", Calendar.app.date(byAdding: .day, value: -1, to: today), Calendar.app.date(byAdding: .day, value: -1, to: today)),
            ("7 ngày qua", Calendar.app.date(byAdding: .day, value: -6, to: today), today),
            ("30 ngày qua", Calendar.app.date(byAdding: .day, value: -29, to: today), today),
        ]
    }

    var body: some View {
        ZStack {
            // Chạm ra ngoài thẻ là đóng.
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            card
                .padding(.horizontal, 24)
        }
    }

    private var card: some View {
        // Hộp thoại nổi GIỮA màn, không phải tấm trượt dính đáy — nên bo cả bốn góc và
        // bỏ thanh kéo, vì thanh kéo là dấu hiệu "kéo xuống để đóng" mà giờ không kéo được.
        VStack(alignment: .leading, spacing: 16) {
            Text("Lọc theo ngày")
                .font(AppFont.beVietnamPro(17, .bold))
                .foregroundStyle(AppColor.payInk)

            FlowChips(presets: presets, dateStart: $dateStart, dateEnd: $dateEnd)

            // Hiện thẳng 2 ô ngày, không phải bấm "Chọn khoảng ngày cụ thể" rồi mới
            // hiện — bỏ 1 bước thừa. Chọn preset ở trên sẽ tự đổ vào 2 ô này, và
            // ngược lại đổi ngày ở đây ghi thẳng vào bộ lọc.
            VStack(spacing: 12) {
                // DatePicker chỉ nhận ClosedRange/PartialRangeFrom cho `in:`, không có
                // overload PartialRangeThrough — dùng distantPast làm cận dưới giả.
                // Ghi vào bộ lọc NGAY TRONG setter của binding, không qua `onChange`:
                // `onChange` chạy ở nhịp cập nhật sau nên không phân biệt được "người dùng
                // vừa chọn ngày" với "vừa nạp giá trị ban đầu" — kết quả là mở sheet lên
                // đã tự lọc theo hôm nay dù chưa chạm gì.
                DatePicker(
                    "Từ ngày",
                    selection: Binding(
                        get: { customStart },
                        set: { customStart = $0; dateStart = $0 }
                    ),
                    in: Date.distantPast...customEnd, displayedComponents: .date
                )
                DatePicker(
                    "Đến ngày",
                    selection: Binding(
                        get: { customEnd },
                        set: { customEnd = $0; dateEnd = $0 }
                    ),
                    in: customStart...Date(), displayedComponents: .date
                )
            }
            .datePickerStyle(.compact)
            // Bấm preset -> đổ ngược vào 2 ô cho khớp. "Tất cả" (nil) giữ nguyên ngày
            // đang hiện, không ghi đè ngược lại bộ lọc.
            .onChangeNewCompat(of: dateStart) { value in
                if let value, !Calendar.app.isDate(value, inSameDayAs: customStart) {
                    customStart = value
                }
            }
            .onChangeNewCompat(of: dateEnd) { value in
                if let value, !Calendar.app.isDate(value, inSameDayAs: customEnd) {
                    customEnd = value
                }
            }

            PrimaryButton(title: "Áp dụng", action: {
                onApply()
                onDismiss()
            })
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 20, y: 8)
        .onAppear {
            // KHÔNG mặc định 7 ngày qua: mở lên mà đã có sẵn khoảng lọc thì người dùng
            // tưởng mình đang xem toàn bộ lịch sử trong khi thực ra đã bị lọc. Chưa lọc
            // gì thì cả hai ô cùng là hôm nay, và chưa ô nào ghi vào bộ lọc.
            let today = Date()
            customStart = dateStart ?? today
            customEnd = dateEnd ?? today
        }
    }
}

/// Chip preset dạng flow-wrap (mirror FlowRow bên Android).
private struct FlowChips: View {
    let presets: [(label: String, start: Date?, end: Date?)]
    @Binding var dateStart: Date?
    @Binding var dateEnd: Date?

    var body: some View {
        // Xếp tràn dòng theo bề rộng THẬT của từng chip. Trước dùng `LazyVGrid` adaptive:
        // nó chia các cột RỘNG BẰNG NHAU nên chip dài như "30 ngày qua" bị ngắt hai dòng
        // khi hộp thoại hẹp lại.
        WrappingRow(spacing: 8, lineSpacing: 8) {
            ForEach(presets, id: \.label) { preset in
                let isActive = isSelected(preset)
                Button {
                    dateStart = preset.start
                    dateEnd = preset.end
                } label: {
                    Text(preset.label)
                        .font(AppFont.beVietnamPro(13, .medium))
                        .foregroundStyle(isActive ? AppColor.brand : AppColor.payMuted)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(isActive ? AppColor.brandSoft : Color.white)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().strokeBorder(isActive ? AppColor.brand : AppColor.payInputBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }

    private func isSelected(_ preset: (label: String, start: Date?, end: Date?)) -> Bool {
        Calendar.app.isDate(dateStart, equalToDateOrNil: preset.start)
            && Calendar.app.isDate(dateEnd, equalToDateOrNil: preset.end)
    }
}

/// Xếp các phần tử theo hàng, hết chỗ thì xuống dòng — mỗi phần tử giữ đúng bề rộng tự
/// nhiên của nó (mirror `FlowRow` bên Compose, SwiftUI không có sẵn).
private struct WrappingRow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widestLine: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth > 0, lineWidth + spacing + size.width > maxWidth {
                totalHeight += lineHeight + lineSpacing
                widestLine = max(widestLine, lineWidth)
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth += lineWidth > 0 ? spacing + size.width : size.width
                lineHeight = max(lineHeight, size.height)
            }
        }
        widestLine = max(widestLine, lineWidth)
        return CGSize(width: min(widestLine, maxWidth), height: totalHeight + lineHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

private extension Calendar {
    func isDate(_ a: Date?, equalToDateOrNil b: Date?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return isDate(a, inSameDayAs: b)
        default: return false
        }
    }
}
