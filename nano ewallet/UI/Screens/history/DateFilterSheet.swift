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
        VStack(alignment: .leading, spacing: 16) {
            Capsule()
                .fill(AppColor.line)
                .frame(width: 40, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

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
                DatePicker(
                    "Từ ngày", selection: $customStart,
                    in: Date.distantPast...customEnd, displayedComponents: .date
                )
                DatePicker(
                    "Đến ngày", selection: $customEnd,
                    in: customStart...Date(), displayedComponents: .date
                )
            }
            .datePickerStyle(.compact)
            .onChange(of: customStart) { _, value in
                if dateStart == nil || !Calendar.app.isDate(value, inSameDayAs: dateStart!) {
                    dateStart = value
                }
            }
            .onChange(of: customEnd) { _, value in
                if dateEnd == nil || !Calendar.app.isDate(value, inSameDayAs: dateEnd!) {
                    dateEnd = value
                }
            }
            // Bấm preset -> đổ ngược vào 2 ô cho khớp. "Tất cả" (nil) giữ nguyên ngày
            // đang hiện, không ghi đè ngược lại bộ lọc.
            .onChange(of: dateStart) { _, value in
                if let value, !Calendar.app.isDate(value, inSameDayAs: customStart) {
                    customStart = value
                }
            }
            .onChange(of: dateEnd) { _, value in
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
        .presentationDragIndicator(.hidden)
        .onAppear {
            // Mở sheet: 2 ô hiện đúng khoảng đang lọc; chưa lọc thì mặc định 7 ngày qua.
            let today = Date()
            customStart = dateStart ?? Calendar.app.date(byAdding: .day, value: -6, to: today) ?? today
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
        // FlowLayout đơn giản bằng LazyVGrid adaptive — đủ dùng cho 5 chip ngắn.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], alignment: .leading, spacing: 8) {
            ForEach(presets, id: \.label) { preset in
                let isActive = isSelected(preset)
                Button {
                    dateStart = preset.start
                    dateEnd = preset.end
                } label: {
                    Text(preset.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isActive ? AppColor.brand : AppColor.payMuted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(isActive ? AppColor.brandSoft : Color.white)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().strokeBorder(isActive ? AppColor.brand : AppColor.payInputBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func isSelected(_ preset: (label: String, start: Date?, end: Date?)) -> Bool {
        Calendar.app.isDate(dateStart, equalToDateOrNil: preset.start)
            && Calendar.app.isDate(dateEnd, equalToDateOrNil: preset.end)
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
