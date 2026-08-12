//
//  PinDotsField.swift
//  nano ewallet
//

import SwiftUI
import Combine

/// Ô nhập mật khẩu 6 chữ số dạng 6 dấu tròn — mirror khối password inline ở
/// LoginScreen / RegisterScreen / WelcomeBackScreen bên Android.
///
/// Cách hoạt động giống Android: 1 `TextField` ẩn (alpha 0) nhận bàn phím số, phía trên
/// vẽ 6 slot. Bấm vào vùng nào cũng focus vào field ẩn.
///
/// Spec Android: box `heightIn(min = 56.dp)`, shadow(8, r16), border 1.dp, slot 14×22.dp,
/// dot 11.dp, khoảng cách 14.dp; chữ hiện 18sp/w600.
struct PinDotsField: View {

    /// `HorizontalAlignment` của SwiftUI không conform `Equatable`, nên không so sánh
    /// `==` được — dùng enum riêng rồi tự map sang alignment lúc layout.
    enum DotsAlignment: Hashable {
        case leading
        case center
    }

    @Binding var value: String
    var placeholder: String = "Nhập mật khẩu"
    var hasError: Bool = false
    /// `.leading` cho Login/Register, `.center` cho WelcomeBack.
    var dotsAlignment: DotsAlignment = .leading
    var submitLabel: SubmitLabel = .done
    var onSubmit: () -> Void = {}
    /// Gọi khi vừa gõ đủ 6 số — dùng để tự nhảy sang ô kế hoặc ẩn bàn phím.
    ///
    /// Cần đường thứ hai KHÔNG phụ thuộc bàn phím: ô này dùng bàn phím SỐ, mà một số bàn
    /// phím không vẽ nút hành động cho kiểu đó — lúc ấy người dùng gõ xong không biết bấm gì.
    /// Độ dài cố định 6 nên cứ đủ số là biết đã xong.
    var onFilled: () -> Void = {}

    /// `true` = KHÔNG dựng `TextField` ẩn, ô chỉ hiển thị và nơi gọi tự bơm số vào `value`
    /// bằng bàn phím tự vẽ (`PlainNumericKeypad`). Lúc đó tiêu điểm do `externalFocus` quyết
    /// định chứ không phải `@FocusState` bên trong — có `TextField` là iOS bật bàn phím hệ
    /// thống lên, hai bàn phím chồng nhau.
    var usesCustomKeypad: Bool = false
    /// Chỉ dùng khi `usesCustomKeypad`: ô này có đang được chọn không (để vẽ caret nháy).
    var externalFocus: Bool = false
    /// Chỉ dùng khi `usesCustomKeypad`: chạm vào ô, nơi gọi chuyển tiêu điểm sang đây.
    var onTapWhenCustom: () -> Void = {}

    @State private var showValue = false
    @FocusState private var internalFocus: Bool
    @State private var caretVisible = true

    /// Tiêu điểm thật, gộp hai chế độ để phần vẽ bên dưới không phải phân biệt.
    private var isFocused: Bool { usesCustomKeypad ? externalFocus : internalFocus }

    /// Nhịp nháy chạy độc lập với vòng đời view. Không dùng
    /// `withAnimation(.repeatForever)` vì animation đó bị huỷ mỗi lần view render
    /// lại — gõ thêm 1 số là `value` đổi -> render lại -> caret đứng im.
    private let caretTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private let maxLength = 6
    private let dotSpacing: CGFloat = 14

    var body: some View {
        ZStack(alignment: .leading) {
            // Field ẩn nhận input. `.keyboardType(.numberPad)` + filter số ở onChange.
            //
            // Bỏ hẳn khi dùng bàn phím tự vẽ: chỉ cần `TextField` tồn tại và được focus là
            // iOS bật bàn phím hệ thống, chồng lên bàn phím tự vẽ.
            if !usesCustomKeypad {
                TextField("", text: $value)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .submitLabel(submitLabel)
                    .focused($internalFocus)
                    .opacity(0)
                    .frame(width: 1, height: 1)
                    .onChangeNewCompat(of: value) { newValue in
                        let filtered = String(newValue.filter(\.isNumber).prefix(maxLength))
                        if filtered != newValue {
                            value = filtered
                            // Đổi `value` sẽ bắn lại `onChange`, để lượt sau báo `onFilled` —
                            // báo ở đây nữa là gọi hai lần cho cùng một lần gõ.
                            return
                        }
                        if filtered.count == maxLength { onFilled() }
                    }
                    .onSubmit(onSubmit)
            }

            if !isFocused && value.isEmpty {
                Text(placeholder)
                    .font(AppFont.beVietnamPro(18))
                    .foregroundStyle(AppColor.payPlaceholder)
                    .frame(
                        maxWidth: .infinity,
                        alignment: dotsAlignment == .center ? .center : .leading
                    )
                    .padding(.leading, dotsAlignment == .center ? 0 : 16)
            } else {
                dots
                    .frame(
                        maxWidth: .infinity,
                        alignment: dotsAlignment == .center ? .center : .leading
                    )
                    .padding(.leading, dotsAlignment == .center ? 0 : 16)
            }

            if !value.isEmpty {
                HStack {
                    Spacer()
                    Button {
                        showValue.toggle()
                    } label: {
                        Image(systemName: showValue ? "eye.slash" : "eye")
                            .font(.system(size: 20))
                            .foregroundStyle(AppColor.payPlaceholder)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .padding(.trailing, 6)
                    .accessibilityLabel(showValue ? "Ẩn mật khẩu" : "Hiện mật khẩu")
                }
            }
        }
        .frame(minHeight: 56)
        .background(hasError ? AppColor.errorSoft : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(hasError ? AppColor.error : AppColor.payInputBorder, lineWidth: 1)
        }
        .inputShadow()
        .contentShape(Rectangle())
        .onTapGesture {
            if usesCustomKeypad {
                // Đặt dấu trước — xem `KeypadDismissGuard`.
                KeypadDismissGuard.markHandled()
                onTapWhenCustom()
            } else {
                internalFocus = true
            }
        }
        .onReceive(caretTimer) { _ in
            guard isFocused else {
                caretVisible = false
                return
            }
            caretVisible.toggle()
        }
        .onChangeCompat(of: isFocused, initial: true) { _, focused in
            // Vừa focus: hiện caret ngay, không phải chờ tới nhịp timer kế tiếp.
            caretVisible = focused
        }
        .onChangeNewCompat(of: value) { _ in
            // Vừa gõ/xoá: caret sáng lại và nhảy sang ô mới ngay, giống caret thật.
            if isFocused { caretVisible = true }
        }
    }

    private var dots: some View {
        HStack(spacing: dotSpacing) {
            ForEach(0..<maxLength, id: \.self) { index in
                let digit = digitAt(index)
                // Ô đang chờ nhập tiếp theo — chỉ 1 ô duy nhất, và chỉ khi field đang focus.
                let isActiveSlot = isFocused && index == value.count

                ZStack {
                    if showValue, let digit {
                        Text(String(digit))
                            .font(AppFont.beVietnamPro(18, .semibold))
                            .foregroundStyle(AppColor.payInk)
                    } else if digit != nil {
                        Circle()
                            .fill(AppColor.payInk)
                            .frame(width: 11, height: 11)
                    } else if isActiveSlot {
                        Rectangle()
                            .fill(AppColor.brand)
                            .frame(width: 2, height: 24)
                            .opacity(caretVisible ? 1 : 0)
                    } else {
                        Circle()
                            .fill(AppColor.payPlaceholder.opacity(0.35))
                            .frame(width: 11, height: 11)
                    }
                }
                .frame(width: 14, height: 22)
            }
        }
    }

    private func digitAt(_ index: Int) -> Character? {
        guard index < value.count else { return nil }
        return value[value.index(value.startIndex, offsetBy: index)]
    }
}
