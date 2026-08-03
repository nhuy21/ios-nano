//
//  FixEkycFieldsView.swift
//  nano ewallet
//
//  Mirror FixEkycFieldsScreen.kt — form sửa các trường Bảo Kim trả về đang sai (status 2)
//  hoặc thiếu (status 3) sau khi nộp hồ sơ.
//
//  Bấm "Cập nhật" gọi `onboarding/update`; nếu kết quả VẪN còn trường lỗi thì màn cha
//  dựng lại form với danh sách mới — vòng này lặp tới khi sạch lỗi.
//

import SwiftUI
import UIKit

struct FixEkycFieldsView: View {

    let fields: [BkField]
    let onBack: () -> Void
    let onResult: (OnboardingResult) -> Void

    @State private var values: [String: String] = [:]
    @State private var isSubmitting = false
    @State private var submitError: String?
    /// Chỉ tô đỏ ô còn trống SAU khi đã bấm Cập nhật ít nhất một lần — vừa vào màn mà
    /// đỏ hết thì trông như đang báo lỗi người dùng chưa hề gây ra.
    @State private var attemptedSubmit = false

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 14) {
                    Text("Bảo Kim cần bạn kiểm tra lại những thông tin dưới đây trước khi mở ví.")
                        .font(AppFont.beVietnamPro(13))
                        .foregroundStyle(AppColor.payMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(fields) { field in
                        fieldRow(field)
                    }

                    if let submitError {
                        Text(submitError)
                            .font(AppFont.beVietnamPro(12))
                            .foregroundStyle(AppColor.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            PrimaryButton(
                title: "Cập nhật",
                loadingTitle: "Đang cập nhật...",
                isLoading: isSubmitting,
                action: submit
            )
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .background(Color.white)
        .onAppear {
            // Điền sẵn giá trị Bảo Kim đang giữ để người dùng sửa chứ không gõ lại từ đầu.
            for field in fields where values[field.key] == nil {
                values[field.key] = field.value ?? ""
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppColor.payInk)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quay lại")

            Text("Bổ sung thông tin")
                .font(AppFont.beVietnamPro(18, .bold))
                .foregroundStyle(AppColor.payInk)

            Spacer(minLength: 0)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func fieldRow(_ field: BkField) -> some View {
        let meta = FixEkycFieldMeta.forKey(field.key)
        let value = values[field.key] ?? ""
        let isEmpty = value.trimmingCharacters(in: .whitespaces).isEmpty
        let showError = attemptedSubmit && isEmpty

        VStack(alignment: .leading, spacing: 6) {
            Text(meta.label)
                .font(AppFont.beVietnamPro(12, .semibold))
                .foregroundStyle(AppColor.payInk)

            if let options = meta.options {
                KycOptionDropdown(
                    title: meta.label,
                    options: options,
                    selectedCode: Binding(
                        get: { values[field.key].flatMap { $0.isEmpty ? nil : $0 } },
                        set: { values[field.key] = $0 ?? "" }
                    ),
                    hasError: showError
                )
            } else {
                TextField("Nhập \(meta.label.lowercased())", text: Binding(
                    get: { values[field.key] ?? "" },
                    set: { values[field.key] = $0 }
                ))
                .font(AppFont.beVietnamPro(14))
                .foregroundStyle(AppColor.payInk)
                .tint(AppColor.brand)
                .keyboardType(meta.isNumeric ? .numberPad : .default)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(showError ? AppColor.error : AppColor.payInputBorder, lineWidth: 1)
                }
            }

            // Lý do Bảo Kim trả về — quan trọng hơn nhãn, vì nó nói CỤ THỂ sai chỗ nào.
            if let message = field.message, !message.isEmpty {
                Text(message)
                    .font(AppFont.beVietnamPro(11))
                    .foregroundStyle(field.status == "3" ? AppColor.payMuted : AppColor.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppColor.payInputBorder, lineWidth: 1)
        }
    }

    private func submit() {
        attemptedSubmit = true
        guard !isSubmitting else { return }
        isSubmitting = true
        submitError = nil
        Task {
            defer { isSubmitting = false }
            // Khoá gửi lên là khoá BE nhận ("name", "placeOfIssues"...), KHÁC khoá Bảo Kim
            // trả về ("kycCn.name") — gửi nhầm khoá thì BE bỏ qua mà không báo lỗi.
            var body: [String: String] = [:]
            for field in fields {
                let meta = FixEkycFieldMeta.forKey(field.key)
                body[meta.updateKey] = (values[field.key] ?? "").trimmingCharacters(in: .whitespaces)
            }
            do {
                let result = try await OnboardingService.updateEkyc(fields: body)
                onResult(result)
            } catch let error as APIError {
                submitError = error.message
            } catch {
                submitError = "Cập nhật thất bại, vui lòng thử lại"
            }
        }
    }
}

/// Ánh xạ khoá Bảo Kim trả về sang nhãn tiếng Việt + khoá gửi cho `onboarding/update`.
/// Bảng theo tài liệu luồng onboarding của Bảo Kim; trường `status 4` (Bảo Kim tự xác
/// thực OTP/NFC/khuôn mặt) không có ở đây vì không sửa qua update được.
struct FixEkycFieldMeta {
    let label: String
    let updateKey: String
    var isNumeric = false
    var options: [KycOption]?

    private static let table: [String: FixEkycFieldMeta] = [
        "kycCn.name": .init(label: "Họ tên", updateKey: "name"),
        "kycCn.birthDay": .init(label: "Ngày sinh (yyyy-MM-dd)", updateKey: "birthDay"),
        "kycCn.nationality": .init(label: "Quốc tịch", updateKey: "nationality"),
        "kycCn.idNumber": .init(label: "Số CCCD", updateKey: "idNumber", isNumeric: true),
        "kycCn.issueDate": .init(label: "Ngày cấp CCCD (yyyy-MM-dd)", updateKey: "issueDate"),
        // Bảo Kim trả về cả hai cách viết, kể cả bản thiếu chữ "s".
        "kycCn.placeOfIssue": .init(label: "Nơi cấp CCCD", updateKey: "placeOfIssues"),
        "kycCn.placeOfIsues": .init(label: "Nơi cấp CCCD", updateKey: "placeOfIssues"),
        "kycCn.recentLocation": .init(label: "Địa chỉ thường trú", updateKey: "recentLocation"),
        "kycCn.temporaryLocation": .init(label: "Địa chỉ tạm trú", updateKey: "temporaryLocation"),
        "kycCn.business": .init(label: "Lĩnh vực kinh doanh", updateKey: "business", options: KycOptions.business),
        "kycCn.position": .init(label: "Chức vụ", updateKey: "position", options: KycOptions.position),
        "kycCn.purposeOfUsing": .init(label: "Mục đích sử dụng ví", updateKey: "purposeOfUsing", options: KycOptions.purposeOfUsing),
        "kycCn.businessAreaId": .init(label: "Khu vực kinh doanh", updateKey: "businessAreaId", options: KycOptions.businessArea),
        "accNo": .init(label: "Số tài khoản ngân hàng", updateKey: "accNo", isNumeric: true),
        "accName": .init(label: "Tên chủ tài khoản", updateKey: "accName"),
        "bankNo": .init(label: "Mã ngân hàng (BIN)", updateKey: "bankNo", isNumeric: true),
    ]

    /// Khoá lạ (Bảo Kim mới thêm) vẫn cho sửa, dùng chính khoá gốc làm nhãn và khoá gửi.
    static func forKey(_ key: String) -> FixEkycFieldMeta {
        table[key] ?? FixEkycFieldMeta(label: key, updateKey: key)
    }
}

/// Ô chọn từ danh sách cố định.
///
/// Mở bảng chọn tự dựng chứ KHÔNG dùng `Menu`: iOS 26 tô nền menu bằng kính mờ nên nhìn
/// xuyên thấy nội dung phía dưới, đọc rối mắt. Bảng tự dựng còn đủ chỗ cho ô tìm kiếm và
/// dấu tích — danh sách ngành nghề có 27 mục, cuộn tay tìm rất mệt.
struct KycOptionDropdown: View {
    var title: String = "Chọn"
    let options: [KycOption]
    @Binding var selectedCode: String?
    var hasError = false

    @State private var isPresented = false

    private var selectedName: String? {
        options.first { $0.code == selectedCode }?.name
    }

    var body: some View {
        Button { isPresented = true } label: {
            HStack {
                Text(selectedName ?? "Vui lòng chọn")
                    .font(AppFont.beVietnamPro(14))
                    .foregroundStyle(selectedName == nil ? AppColor.payMuted : AppColor.payInk)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.payMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(hasError ? AppColor.error : AppColor.payInputBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        // `fullScreenCover` nền trong suốt rồi tự vẽ lớp mờ + thẻ, thay vì `sheet` hệ
        // thống: sheet nhiều nấc thì cuộn danh sách lại kéo giãn cả bảng làm tiêu đề
        // trôi lên, và vùng mờ của nó không nhận chạm để đóng.
        .fullScreenCover(isPresented: $isPresented) {
            KycOptionPickerSheet(
                title: title,
                options: options,
                selectedCode: $selectedCode,
                onDismiss: { isPresented = false }
            )
            .presentationBackground(.clear)
        }
    }
}

/// Bảng chọn: tiêu đề, ô tìm kiếm khi danh sách dài, mỗi dòng có dấu tích khi đang chọn.
struct KycOptionPickerSheet: View {
    let title: String
    let options: [KycOption]
    @Binding var selectedCode: String?
    let onDismiss: () -> Void

    @State private var query = ""

    /// Ngưỡng hiện ô tìm kiếm — dưới ngưỡng thì lướt mắt nhanh hơn gõ.
    private var showsSearch: Bool { options.count > 8 }

    /// Trần chiều cao vùng cuộn = 55% màn hình. Lấy qua `windowScene.screen` thay
    /// `UIScreen.main` (deprecated iOS 26); không có scene thì rơi về 872pt (iPhone 15).
    private var maxListHeight: CGFloat {
        let screenHeight = (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)?
            .screen.bounds.height
        return (screenHeight ?? 872) * 0.55
    }

    private var filtered: [KycOption] {
        let needle = query.trimmingCharacters(in: .whitespaces).noAccentLowercasedKyc
        guard !needle.isEmpty else { return options }
        return options.filter { $0.name.noAccentLowercasedKyc.contains(needle) }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Chạm ra ngoài thẻ là đóng.
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            card
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var card: some View {
        VStack(spacing: 0) {
            // Tiêu đề và ô tìm kiếm nằm NGOÀI vùng cuộn nên đứng yên khi lướt danh sách.
            Capsule()
                .fill(AppColor.line)
                .frame(width: 40, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 12)

            Text(title)
                .font(AppFont.beVietnamPro(16, .bold))
                .foregroundStyle(AppColor.payInk)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            if showsSearch {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppColor.payMuted)
                    TextField("Tìm nhanh", text: $query)
                        .font(AppFont.beVietnamPro(14))
                        .tint(AppColor.brand)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(hex: 0xF1F3F5))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filtered) { option in
                        row(option)
                    }

                    if filtered.isEmpty {
                        Text("Không tìm thấy mục phù hợp")
                            .font(AppFont.beVietnamPro(13))
                            .foregroundStyle(AppColor.payMuted)
                            .padding(.top, 24)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            // Chỉ giới hạn chiều cao của VÙNG CUỘN, không giới hạn cả thẻ: đặt ở thẻ thì
            // phần đầu bị đẩy khỏi khung, danh sách hiện từ giữa chừng. Cách này danh sách
            // ngắn thì thẻ co vừa đủ, dài thì cuộn bên trong.
            //
            // `maxListHeight` đọc màn hình qua `connectedScenes` thay `UIScreen.main`
            // (deprecated iOS 26) — vẫn là `maxHeight` nên danh sách ngắn KHÔNG bị giãn
            // (khác `containerRelativeFrame`, cái đó ép đúng bằng tỉ lệ).
            .frame(maxHeight: maxListHeight)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(.rect(topLeadingRadius: 24, topTrailingRadius: 24))
    }

    private func row(_ option: KycOption) -> some View {
        let isSelected = option.code == selectedCode
        return Button {
            selectedCode = option.code
            onDismiss()
        } label: {
            HStack(spacing: 12) {
                Text(option.name)
                    .font(AppFont.beVietnamPro(14, isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AppColor.brand : AppColor.payInk)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(AppColor.brand)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? AppColor.brandSoft : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? AppColor.brand : AppColor.payInputBorder,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

private extension String {
    /// Tìm không phân biệt dấu — gõ "nganh nghe" vẫn ra "ngành nghề".
    var noAccentLowercasedKyc: String {
        folding(options: .diacriticInsensitive, locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")
            .lowercased()
    }
}

#Preview {
    FixEkycFieldsView(
        fields: [
            BkField(key: "kycCn.temporaryLocation", value: "", status: "3", message: "Thiếu địa chỉ tạm trú"),
            BkField(key: "kycCn.name", value: "NGUYEN VAN A", status: "2", message: "Họ tên không khớp giấy tờ"),
            BkField(key: "kycCn.position", value: nil, status: "3", message: nil),
        ],
        onBack: {}, onResult: { _ in }
    )
}
