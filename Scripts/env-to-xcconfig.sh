#!/bin/bash
# Sinh Config.xcconfig từ .env để Xcode đọc được (Xcode không hỗ trợ .env trực tiếp).
#
# Cách dùng:
#   - Chạy tay:  ./Scripts/env-to-xcconfig.sh
#   - Hoặc thêm vào Xcode: target > Build Phases > "+" > New Run Script Phase,
#     kéo lên TRƯỚC "Compile Sources", nội dung:
#         "$SRCROOT/Scripts/env-to-xcconfig.sh"
#     và bỏ tick "Based on dependency analysis" để luôn chạy lại.

set -euo pipefail

# Thư mục gốc repo = cha của Scripts/
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env"
OUT_FILE="$ROOT/Config.xcconfig"

if [ ! -f "$ENV_FILE" ]; then
    echo "error: Không tìm thấy $ENV_FILE — copy .env.example thành .env rồi thử lại." >&2
    exit 1
fi

{
    echo "// File này được sinh tự động từ .env bởi Scripts/env-to-xcconfig.sh"
    echo "// KHÔNG sửa tay, KHÔNG commit — mọi thay đổi sẽ bị ghi đè."
    echo ""

    # Bỏ dòng trống và dòng comment; giữ nguyên KEY=VALUE.
    # Lưu ý: '//' trong URL (https://) là comment trong cú pháp xcconfig, nên phải
    # tách thành biến phụ rồi ghép lại — thủ thuật chuẩn cho xcconfig.
    while IFS='=' read -r key value || [ -n "$key" ]; do
        # Trim khoảng trắng
        key="$(echo "$key" | xargs)"
        [ -z "$key" ] && continue
        case "$key" in \#*) continue ;; esac

        value="$(echo "$value" | xargs)"

        if [[ "$value" == *"//"* ]]; then
            scheme="${value%%//*}"      # "https:"
            rest="${value#*//}"         # "host/path"
            echo "${key}_SCHEME = ${scheme}"
            echo "${key}_REST = ${rest}"
            echo "SLASH = /"
            echo "${key} = \$(${key}_SCHEME)\$(SLASH)\$(SLASH)\$(${key}_REST)"
        else
            echo "${key} = ${value}"
        fi
    done < "$ENV_FILE"
} > "$OUT_FILE"

echo "Đã sinh $OUT_FILE từ .env"
