//
//  TermsOfUseView.swift
//  nano ewallet
//
//  Mirror TermsOfUseScreen.kt — màn chỉ đọc, 14 block điều khoản tĩnh, không API.
//

import SwiftUI

private struct TermsBlock {
    let title: String
    let body: String
}

private let termsBlocks: [TermsBlock] = [
    TermsBlock(
        title: "1. Giới thiệu",
        body: "Ví nano là ứng dụng ví điện tử cho phép bạn mở ví, nạp/rút tiền, chuyển tiền và thanh toán trên thiết bị di động. Dịch vụ ví điện tử được cung cấp thông qua Bảo Kim — đối tác trung gian thanh toán được Ngân hàng Nhà nước Việt Nam cấp phép. Khi đăng ký và sử dụng Ví nano, bạn xác nhận đã đọc, hiểu và đồng ý với toàn bộ các điều khoản dưới đây."
    ),
    TermsBlock(
        title: "2. Định nghĩa",
        body: "• \"Ứng dụng\" / \"Ví nano\": phần mềm ví điện tử trên thiết bị di động của bạn.\n• \"Bảo Kim\": tổ chức cung ứng dịch vụ trung gian thanh toán được cấp phép, đơn vị nắm giữ và xử lý số dư ví của bạn.\n• \"Ví\": tài khoản ví điện tử được định danh bằng số điện thoại của bạn; một số điện thoại có thể có một hoặc nhiều ví.\n• \"eKYC\": quy trình định danh điện tử bằng CCCD gắn chip, quét NFC và xác thực khuôn mặt."
    ),
    TermsBlock(
        title: "3. Điều kiện sử dụng",
        body: "Bạn phải từ đủ 15 tuổi trở lên, có Căn cước công dân (CCCD) gắn chip hợp lệ và số điện thoại chính chủ đang hoạt động. Mỗi cá nhân sử dụng thông tin định danh của chính mình; không được mở hoặc sử dụng ví bằng giấy tờ của người khác. Bạn chịu trách nhiệm về tính chính xác của thông tin đã cung cấp."
    ),
    TermsBlock(
        title: "4. Mở ví & Định danh (eKYC)",
        body: "Để mở ví, bạn thực hiện định danh điện tử: chụp CCCD gắn chip, quét chip NFC và xác thực khuôn mặt (liveness). Trường hợp đã có ví Bảo Kim, bạn có thể liên kết bằng cách nhập họ tên và số ví, sau đó xác nhận mã OTP do Bảo Kim gửi tới số điện thoại đã đăng ký. Ví nano và Bảo Kim có quyền từ chối mở/liên kết ví nếu thông tin định danh không hợp lệ hoặc không khớp."
    ),
    TermsBlock(
        title: "5. Vai trò của Bảo Kim",
        body: "Số dư trong ví của bạn được nắm giữ, quản lý và xử lý bởi Bảo Kim theo quy định pháp luật về trung gian thanh toán. Ví nano đóng vai trò giao diện và kênh truy cập dịch vụ. Các giao dịch, hạn mức và việc lưu ký tiền tuân theo quy định của Bảo Kim và Ngân hàng Nhà nước."
    ),
    TermsBlock(
        title: "6. Dịch vụ cung cấp",
        body: "Ví nano hỗ trợ: chuyển tiền giữa các ví, chuyển tiền tới tài khoản ngân hàng, rút tiền về tài khoản/ngân hàng đã liên kết, nạp tiền vào ví, quét mã QR (VietQR) để thanh toán/chuyển khoản, theo dõi và quản lý chi tiêu. Danh mục dịch vụ có thể được cập nhật, bổ sung hoặc ngừng cung cấp theo từng thời điểm."
    ),
    TermsBlock(
        title: "7. Giao dịch, hạn mức & phí",
        body: "Bạn có trách nhiệm kiểm tra kỹ thông tin người nhận và số tiền trước khi xác nhận. Giao dịch đã xác nhận thành công là không thể hủy hoặc hoàn tác. Nếu phát sinh sai sót, vui lòng liên hệ hỗ trợ sớm nhất có thể. Hạn mức giao dịch tuân theo quy định của Bảo Kim và Ngân hàng Nhà nước. Phí dịch vụ (nếu có) sẽ được hiển thị trước khi bạn xác nhận giao dịch.\n\nĐể bảo vệ tài khoản, mỗi giao dịch được xác thực theo mức số tiền:\n• Dưới 500.000đ: thực hiện ngay, không cần xác thực.\n• Từ 500.000đ trở lên: yêu cầu nhập mã PIN.\n\nHạn mức chuyển tiền:\n• Tối đa 10.000.000đ cho mỗi giao dịch.\n• Tối đa 20.000.000đ tổng trong một ngày.\n• Tối đa 100.000.000đ tổng trong một tháng."
    ),
    TermsBlock(
        title: "8. Trách nhiệm của người dùng",
        body: "Bạn có trách nhiệm bảo mật mật khẩu, mã PIN, mã OTP và thiết bị đăng nhập; không chia sẻ cho bất kỳ ai. Mọi giao dịch được thực hiện bằng thông tin xác thực của bạn được xem là do bạn thực hiện. Nghiêm cấm sử dụng ví cho mục đích rửa tiền, tài trợ khủng bố, lừa đảo, cờ bạc hoặc bất kỳ hoạt động trái pháp luật nào."
    ),
    TermsBlock(
        title: "9. Bảo mật & Dữ liệu cá nhân",
        body: "Ví nano thu thập và xử lý thông tin cá nhân (bao gồm dữ liệu định danh và sinh trắc học) nhằm mở ví, cung cấp dịch vụ và tuân thủ quy định pháp luật. Dữ liệu được bảo vệ bằng mã hoá và xác thực sinh trắc học, không được chia sẻ cho bên thứ ba ngoài Bảo Kim, các đối tác cần thiết để cung cấp dịch vụ và cơ quan nhà nước có thẩm quyền theo quy định."
    ),
    TermsBlock(
        title: "10. Tạm khoá & Chấm dứt",
        body: "Ví nano và/hoặc Bảo Kim có quyền tạm khoá hoặc chấm dứt quyền sử dụng ví của bạn nếu phát hiện vi phạm điều khoản, có dấu hiệu gian lận, giao dịch bất thường hoặc theo yêu cầu của cơ quan có thẩm quyền. Bạn có thể yêu cầu đóng ví bất kỳ lúc nào sau khi hoàn tất các nghĩa vụ liên quan."
    ),
    TermsBlock(
        title: "11. Giới hạn trách nhiệm",
        body: "Ví nano không chịu trách nhiệm đối với các thiệt hại gián tiếp, ngẫu nhiên hoặc hệ quả phát sinh từ việc sử dụng hoặc không thể sử dụng dịch vụ, bao gồm nhưng không giới hạn ở gián đoạn kết nối, lỗi thiết bị của người dùng, hoặc các sự kiện bất khả kháng nằm ngoài khả năng kiểm soát hợp lý."
    ),
    TermsBlock(
        title: "12. Thay đổi điều khoản",
        body: "Các điều khoản này có thể được cập nhật theo từng thời điểm để phù hợp với quy định pháp luật và sự thay đổi của dịch vụ. Phiên bản cập nhật sẽ có hiệu lực khi được công bố trong ứng dụng. Việc bạn tiếp tục sử dụng Ví nano đồng nghĩa với việc chấp thuận các thay đổi đó."
    ),
    TermsBlock(
        title: "13. Luật áp dụng & Giải quyết tranh chấp",
        body: "Các điều khoản này được điều chỉnh bởi pháp luật Việt Nam. Mọi tranh chấp phát sinh sẽ được ưu tiên giải quyết thông qua thương lượng; nếu không đạt được thoả thuận, tranh chấp sẽ được đưa ra cơ quan có thẩm quyền tại Việt Nam để giải quyết."
    ),
    TermsBlock(
        title: "14. Liên hệ",
        body: "Mọi thắc mắc hoặc yêu cầu hỗ trợ liên quan đến điều khoản và dịch vụ, vui lòng liên hệ qua email: nhiep9145@gmail.com."
    ),
]

struct TermsOfUseView: View {
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(title: "Điều khoản sử dụng", onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Điều khoản sử dụng Ví nano")
                        .font(AppFont.beVietnamPro(20, .bold))
                        .foregroundStyle(AppColor.brand)

                    Spacer().frame(height: 4)

                    Text("Cập nhật lần cuối: 11/07/2026")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColor.payMuted)

                    Spacer().frame(height: 20)

                    ForEach(termsBlocks.indices, id: \.self) { index in
                        let block = termsBlocks[index]
                        Text(block.title)
                            .font(AppFont.beVietnamPro(15, .semibold))
                            .foregroundStyle(AppColor.payInk)

                        Spacer().frame(height: 6)

                        Text(block.body)
                            .font(.system(size: 13.5))
                            .foregroundStyle(AppColor.payMuted)
                            .lineSpacing(6)
                            .multilineTextAlignment(.leading)

                        Spacer().frame(height: 18)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
        }
        .background(Color(hex: 0xF5F7F6))
    }
}

#Preview {
    TermsOfUseView(onBack: {})
}
