//
//  KycOptions.swift
//  nano ewallet
//
//  Mirror ekyc/KycOptions.kt — danh sách cố định cho 4 trường bổ sung mà Bảo Kim đòi
//  trong payload kycCn. Bảo Kim chưa có API tra cứu nên ghi cứng, giống Android.
//

import Foundation

struct KycOption: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }
}

enum KycOptions {

    static let business: [KycOption] = [
        KycOption(code: "1", name: "Giáo viên / Bác sĩ / Kỹ sư"),
        KycOption(code: "2", name: "Nhân viên văn phòng"),
        KycOption(code: "3", name: "Nhân viên dịch vụ/bán hàng"),
        KycOption(code: "4", name: "Kinh doanh tự do"),
        KycOption(code: "5", name: "Học sinh/sinh viên"),
        KycOption(code: "6", name: "Lực lượng vũ trang"),
        KycOption(code: "7", name: "Nông dân/Công nhân/Ngư dân"),
        KycOption(code: "8", name: "Công chức/viên chức"),
        KycOption(code: "9", name: "Doanh nghiệp"),
    ]

    static let position: [KycOption] = [
        KycOption(code: "1", name: "Giám đốc"),
        KycOption(code: "2", name: "Giám đốc kinh doanh"),
        KycOption(code: "3", name: "Giám đốc tài chính"),
        KycOption(code: "4", name: "Giám đốc vận hành"),
        KycOption(code: "5", name: "Phó giám đốc"),
        KycOption(code: "6", name: "Kế toán trưởng"),
        KycOption(code: "7", name: "Chủ hộ kinh doanh"),
        KycOption(code: "8", name: "Trưởng phòng kinh doanh"),
        KycOption(code: "9", name: "Chủ tịch HĐQT"),
        KycOption(code: "10", name: "Khác"),
        KycOption(code: "11", name: "Tổng giám đốc"),
    ]

    static let purposeOfUsing: [KycOption] = [
        KycOption(code: "1", name: "Thanh toán hàng hóa, dịch vụ"),
        KycOption(code: "2", name: "Nộp phí, lệ phí cho các dịch vụ công"),
        KycOption(code: "3", name: "Nhận quyết toán từ việc bán hàng hóa, dịch vụ"),
        KycOption(code: "4", name: "Nhận / chuyển tiền"),
        KycOption(code: "5", name: "Đầu tư, kinh doanh"),
    ]

    static let businessArea: [KycOption] = [
        KycOption(code: "001", name: "Điện tử"),
        KycOption(code: "002", name: "Đồ gia dụng, nội thất, thiết kế"),
        KycOption(code: "003", name: "Quần áo, giày dép, phụ kiện"),
        KycOption(code: "004", name: "Sách, Văn phòng phẩm"),
        KycOption(code: "005", name: "Cửa hàng thực phẩm, địa điểm ăn uống"),
        KycOption(code: "006", name: "Đồ uống có cồn, thuốc lá"),
        KycOption(code: "007", name: "Trang sức, đá quý, đồng hồ, phụ kiện cao cấp"),
        KycOption(code: "008", name: "Hóa chất"),
        KycOption(code: "009", name: "Phương tiện đi lại"),
        KycOption(code: "010", name: "Trường học, khóa học đào tạo"),
        KycOption(code: "011", name: "Tổ chức tài chính, phi tài chính"),
        KycOption(code: "012", name: "Thuế, phí, dịch vụ công"),
        KycOption(code: "013", name: "Dịch vụ đặt phòng"),
        KycOption(code: "014", name: "Thuê và cho thuê bất động sản"),
        KycOption(code: "015", name: "Dịch vụ mạng, dịch vụ trực tuyến"),
        KycOption(code: "016", name: "Dịch vụ khác"),
        KycOption(code: "017", name: "Dịch vụ du lịch"),
        KycOption(code: "018", name: "Y tế"),
        KycOption(code: "019", name: "Mỹ phẩm, spa làm đẹp"),
        KycOption(code: "020", name: "Dịch vụ bảo hiểm"),
        KycOption(code: "021", name: "Dịch vụ thể thao, trò chơi, dịch vụ giải trí số"),
        KycOption(code: "022", name: "Dịch vụ viễn thông"),
        KycOption(code: "023", name: "Giải pháp phần mềm, hệ thống quản lý"),
        KycOption(code: "024", name: "Nhạc cụ"),
        KycOption(code: "025", name: "Xây dựng, cơ khí"),
        KycOption(code: "026", name: "Sòng bạc, xổ số, cá cược"),
        KycOption(code: "027", name: "Tiếp thị trực tiếp"),
    ]
}
