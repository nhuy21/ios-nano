//
//  TransactionDisplay.swift
//  nano ewallet
//
//  Mapper dùng chung cho icon/màu/title theo type+status — mirror bảng màu trong
//  HistoryScreen.kt + TransactionDetailSheet.kt (2 file Kotlin lặp lại y hệt bảng
//  này, gộp về 1 chỗ ở đây cho gọn).
//

import SwiftUI

enum TransactionDisplay {

    /// Title cho dòng danh sách (HistoryScreen/HomeScreen) — có tên bank trong ngoặc.
    static func listTitle(for tx: TransactionEntity) -> String {
        switch tx.kind {
        case .topUp:
            return "Nạp tiền vào ví"
        case .withdraw:
            return "Rút tiền về ngân hàng liên kết"
        case .transferIn:
            return tx.benAccName.map { "Nhận tiền từ \($0)" } ?? "Nhận tiền"
        case .refund:
            return "Hoàn tiền giao dịch thất bại"
        case .transferOut:
            if let bankName = tx.benBankName {
                if let name = tx.benAccName {
                    return "Thanh toán cho \(name) (\(bankName))"
                }
                return "Thanh toán (\(bankName))"
            }
            if let name = tx.benAccName {
                return "Chuyển tiền đến \(name)"
            }
            return "Chuyển tiền"
        case .none:
            return tx.benAccName.map { "Giao dịch với \($0)" } ?? "Giao dịch"
        }
    }

    /// Title cho TransactionDetailSheet — KHÔNG kèm tên bank trong ngoặc (khác listTitle).
    static func detailTitle(for tx: TransactionEntity) -> String {
        switch tx.kind {
        case .topUp:
            return "Nạp tiền vào ví"
        case .withdraw:
            return "Rút tiền về ngân hàng liên kết"
        case .transferIn:
            return tx.benAccName.map { "Nhận tiền từ \($0)" } ?? "Nhận tiền"
        case .refund:
            return "Hoàn tiền giao dịch thất bại"
        case .transferOut:
            if tx.benBankName != nil {
                if let name = tx.benAccName {
                    return "Thanh toán cho \(name)"
                }
                return "Thanh toán qua ngân hàng"
            }
            if let name = tx.benAccName {
                return "Chuyển tiền đến \(name)"
            }
            return "Chuyển tiền"
        case .none:
            return "Giao dịch"
        }
    }

    static func typeLabel(for tx: TransactionEntity) -> String {
        switch tx.kind {
        case .topUp: return "Nạp tiền"
        case .withdraw: return "Rút tiền"
        case .transferIn: return "Nhận tiền"
        case .refund: return "Hoàn tiền"
        case .transferOut: return tx.benBankName != nil ? "Thanh toán ngân hàng" : "Chuyển tiền"
        case .none: return "Giao dịch"
        }
    }

    /// (icon SF Symbol, màu nền pastel, màu icon) — theo type, bị status FAILED/PENDING ghi đè.
    static func iconStyle(for tx: TransactionEntity) -> (systemImage: String, background: Color, tint: Color) {
        if isFailedStatus(tx) {
            return ("xmark.circle.fill", Color(hex: 0xFFE3D6), Color(hex: 0xE8531F))
        }
        if isPendingStatus(tx) {
            return (pendingIcon(for: tx), Color(hex: 0xFFF6D9), Color(hex: 0xE6A200))
        }
        switch tx.kind {
        case .topUp:
            return ("wallet.pass.fill", Color(hex: 0xFFF1E0), Color(hex: 0xF5901E))
        case .withdraw:
            return ("arrow.down.circle.fill", Color(hex: 0xECEAFF), Color(hex: 0x6A6AF5))
        case .transferIn:
            return ("arrow.down.left.circle.fill", Color(hex: 0xE4F6EC), Color(hex: 0x22A45D))
        case .refund:
            return ("arrow.uturn.left.circle.fill", Color(hex: 0xE0EAFF), Color(hex: 0x1A3FBF))
        case .transferOut:
            if tx.benBankName != nil {
                return ("building.columns.fill", Color(hex: 0xE3F1FF), Color(hex: 0x2C93E8))
            }
            return ("arrow.up.right.circle.fill", Color(hex: 0xFFE8E1), Color(hex: 0xE5484D))
        case .none:
            return ("circle.fill", Color(hex: 0xF6F7F9), AppColor.payMuted)
        }
    }

    /// (text, textColor, background) badge trạng thái — dùng ở TransactionDetailSheet.
    static func statusMeta(for tx: TransactionEntity) -> (text: String, color: Color, background: Color) {
        switch tx.statusKind {
        case .success:
            return ("Giao dịch thành công", Color(hex: 0x00A85E), Color(hex: 0xE6F7EE))
        case .pending, .processing:
            return ("Đang xử lý", Color(hex: 0xF5901E), Color(hex: 0xFFF1E0))
        case .failed, .cancelled:
            return ("Giao dịch thất bại", Color(hex: 0xE5484D), Color(hex: 0xFFE8E1))
        case .none:
            return (tx.status, AppColor.payMuted, Color(hex: 0xF6F7F9))
        }
    }

    /// Tiền vào hiện xanh, tiền ra hiện mực đen (KHÔNG dùng đỏ cho tiền ra — đúng bản gốc).
    static func amountColor(for tx: TransactionEntity) -> Color {
        tx.isIncome ? Color(hex: 0x19B36B) : AppColor.payInk
    }

    private static func isFailedStatus(_ tx: TransactionEntity) -> Bool {
        switch tx.statusKind {
        case .failed, .cancelled: return true
        default: return false
        }
    }

    private static func isPendingStatus(_ tx: TransactionEntity) -> Bool {
        switch tx.statusKind {
        case .pending, .processing: return true
        default: return false
        }
    }

    private static func pendingIcon(for tx: TransactionEntity) -> String {
        iconStyleIgnoringStatus(for: tx.kind)
    }

    private static func iconStyleIgnoringStatus(for kind: TransactionType?) -> String {
        switch kind {
        case .topUp: return "wallet.pass.fill"
        case .withdraw: return "arrow.down.circle.fill"
        case .transferIn: return "arrow.down.left.circle.fill"
        case .refund: return "arrow.uturn.left.circle.fill"
        case .transferOut: return "arrow.up.right.circle.fill"
        case .none: return "circle.fill"
        }
    }
}
