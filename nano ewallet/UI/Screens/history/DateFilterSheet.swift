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
    @State private var showingCustomPicker = false

    private var presets: [(label: String, start: Date?, end: Date?)] {
        let today = Calendar.current.startOfDay(for: Date())
        return [
            ("Tất cả", nil, nil),
            ("Hôm nay", today, today),
            ("Hôm qua", Calendar.current.date(byAdding: .day, value: -1, to: today), Calendar.current.date(byAdding: .day, value: -1, to: today)),
            ("7 ngày qua", Calendar.current.date(byAdding: .day, value: -6, to: today), today),
            ("30 ngày qua", Calendar.current.date(byAdding: .day, value: -29, to: today), today),
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

            if !showingCustomPicker {
                Button {
                    customStart = dateStart ?? Date()
                    customEnd = dateEnd ?? Date()
                    showingCustomPicker = true
                } label: {
                    HStack {
                        Image(systemName: "calendar")
                        Text("Chọn khoảng ngày cụ thể")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(AppColor.payInk)
                    .padding(14)
                    .background(Color(hex: 0xF6F7F9))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
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

                Button("Áp dụng khoảng ngày") {
                    dateStart = customStart
                    dateEnd = customEnd
                    showingCustomPicker = false
                }
                .buttonStyle(.plain)
                .font(AppFont.beVietnamPro(14, .semibold))
                .foregroundStyle(AppColor.brand)
            }

            PrimaryButton(title: "Áp dụng", action: {
                onApply()
                onDismiss()
            })
        }
        .padding(20)
        .presentationDragIndicator(.hidden)
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
        Calendar.current.isDate(dateStart, equalToDateOrNil: preset.start)
            && Calendar.current.isDate(dateEnd, equalToDateOrNil: preset.end)
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
