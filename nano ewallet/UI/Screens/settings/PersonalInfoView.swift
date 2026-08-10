//
//  PersonalInfoView.swift
//  nano ewallet
//
//  Mirror PersonalInfoScreen.kt — hiện hồ sơ đã có sẵn trong DB (họ tên, ngày sinh, số CCCD
//  che giữa, giới tính, badge xác thực eKYC, số điện thoại, email). Chỉ ĐỌC, không sửa được:
//  thông tin giấy tờ lấy từ eKYC nên muốn đổi phải làm lại eKYC, không phải gõ tay.
//

import SwiftUI

struct PersonalInfoView: View {
    let onBack: () -> Void

    @StateObject private var authStore = AuthStore.shared

    @State private var profile: UserProfile?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(title: "Thông tin cá nhân", onBack: onBack)

            content
        }
        .screenBackground(Color.white)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .tint(AppColor.brand)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            Text(errorMessage)
                .font(AppFont.beVietnamPro(14))
                .foregroundStyle(AppColor.payMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let profile {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    avatar

                    Spacer().frame(height: 20)

                    groupLabel("THÔNG TIN GIẤY TỜ TÙY THÂN")

                    infoCard {
                        infoRow("Họ và tên", value: displayOrDash(profile.fullName))
                        divider
                        infoRow("Ngày sinh", value: Self.formatBirthDay(profile.birthDay))
                        divider
                        infoRow("Số CCCD/CMND", value: Self.maskIdNumber(profile.idNumber))
                        divider
                        infoRow("Giới tính", value: Self.genderLabel(profile.gender))
                    }

                    // Chỉ hiện khi đã eKYC xong — trạng thái khác thì không có gì để khoe,
                    // hiện badge xám "chưa xác thực" chỉ tổ làm người dùng lo.
                    if profile.kycStatus == "ACTIVATED" {
                        Spacer().frame(height: 10)
                        verifiedBadge
                    }

                    Spacer().frame(height: 24)

                    groupLabel("THÔNG TIN LIÊN HỆ")

                    infoCard {
                        infoRow("Số điện thoại", value: Self.normalizePhone(profile.phone))
                        divider
                        infoRow("Email", value: profile.email)
                    }

                    Spacer().frame(height: 32)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Thành phần

    private var avatar: some View {
        Circle()
            .fill(AppColor.brandSoft)
            .frame(width: 88, height: 88)
            .overlay {
                Text(initials)
                    .font(AppFont.beVietnamPro(32, .heavy))
                    .foregroundStyle(AppColor.brand)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }

    /// Chữ cái đầu của họ và của tên — dùng chung `nameInitials` với màn Cá nhân để hai nơi
    /// không bao giờ ra kết quả khác nhau.
    ///
    /// Ưu tiên tên vừa lấy từ API hơn tên trong cache: màn này đã gọi `users/me` nên có bản
    /// mới nhất, còn cache có thể là tên cũ từ lần đăng nhập trước.
    private var initials: String {
        // `profile?.fullName` là `String??` (cả profile lẫn fullName đều optional) nên phải
        // gỡ hai lớp bằng `??` chứ không dùng `flatMap` được.
        let fromApi = (profile?.fullName ?? nil).flatMap { $0.isEmpty ? nil : $0 }
        let name = fromApi ?? authStore.userFullName ?? "Người dùng Nano"
        return name.nameInitials
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text)
            .font(AppFont.beVietnamPro(12.5, .semibold))
            .foregroundStyle(AppColor.payMuted)
            .padding(.leading, 4)
            .padding(.bottom, 8)
    }

    private func infoCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, 16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(AppFont.beVietnamPro(13.5))
                .foregroundStyle(AppColor.payMuted)
            Spacer(minLength: 8)
            Text(value)
                .font(AppFont.beVietnamPro(15, .semibold))
                .foregroundStyle(AppColor.payInk)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 14)
    }

    private var divider: some View {
        Rectangle()
            .fill(AppColor.line)
            .frame(height: 1)
    }

    private var verifiedBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 17))
                .foregroundStyle(AppColor.brand)
            Text("Đã xác thực định danh qua eKYC")
                .font(AppFont.beVietnamPro(13.5, .semibold))
                .foregroundStyle(AppColor.brand)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppColor.brandSoft)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Tải dữ liệu

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            profile = try await AccountService.getMyProfile()
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Không tải được thông tin cá nhân"
        }
    }

    // MARK: - Định dạng

    private func displayOrDash(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return "—" }
        return value
    }

    /// "84912345678" -> "0912345678". BE/Bảo Kim lưu SĐT dạng quốc tế, hiển thị dạng quen
    /// thuộc với người Việt. Số đã có dạng 0 hoặc không khớp định dạng thì giữ nguyên.
    static func normalizePhone(_ phone: String) -> String {
        guard phone.hasPrefix("84"), phone.count == 11 else { return phone }
        return "0" + phone.dropFirst(2)
    }

    /// "001199012345" -> "0011••••••45" (giữ 4 số đầu + 2 số cuối, còn lại che).
    static func maskIdNumber(_ idNumber: String?) -> String {
        guard let idNumber, !idNumber.trimmingCharacters(in: .whitespaces).isEmpty else { return "—" }
        guard idNumber.count > 6 else { return idNumber }
        let head = idNumber.prefix(4)
        let tail = idNumber.suffix(2)
        return head + String(repeating: "•", count: idNumber.count - 6) + tail
    }

    static func genderLabel(_ gender: Int?) -> String {
        switch gender {
        case 1: return "Nam"
        case 2: return "Nữ"
        case 3: return "Khác"
        default: return "—"
        }
    }

    /// ISO-8601 ("2003-01-23T00:00:00.000Z") -> "23/01/2003". Sai định dạng thì trả nguyên bản.
    static func formatBirthDay(_ birthDay: String?) -> String {
        guard let birthDay, !birthDay.trimmingCharacters(in: .whitespaces).isEmpty else { return "—" }
        guard let date = ISO8601DateFormatter.withFractionalSeconds.date(from: birthDay)
            ?? ISO8601DateFormatter.standard.date(from: birthDay) else {
            return birthDay
        }
        // Ngày sinh BE lưu ở mốc 00:00 UTC — format theo giờ máy sẽ lùi một ngày ở múi giờ
        // âm, nên ghim UTC cho khớp đúng ngày đã nhập lúc eKYC.
        let formatter = DateFormatter.app("dd/MM/yyyy")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}

#Preview {
    PersonalInfoView(onBack: {})
}
