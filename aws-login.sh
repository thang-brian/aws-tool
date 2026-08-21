#!/bin/bash

# --- KIỂM TRA CẬP NHẬT TỰ ĐỘNG ---
if [ -f "$HOME/scripts/updater.sh" ]; then
    source "$HOME/scripts/updater.sh"
    check_for_updates
fi
# ---------------------------------

echo "🧹 Đang dọn dẹp cấu hình credentials cũ..."

CRED_FILE="$HOME/.aws/credentials"
if [ -f "$CRED_FILE" ]; then
    # Backup file
    cp "$CRED_FILE" "${CRED_FILE}.bak"
    # Thêm # vào đầu tất cả các dòng (trừ những dòng trống và dòng đã có #)
    sed -i.bak -e '/^[[:space:]]*$/! s/^\([^#]\)/# \1/' "$CRED_FILE"
    rm -f "${CRED_FILE}.bak"
    echo "   ✅ Đã backup và comment out thành công các key cũ trong ~/.aws/credentials"
else
    echo "   ✅ Không tìm thấy file ~/.aws/credentials. Bạn đã sạch sẽ!"
fi

echo ""
echo "=================================================="
echo "🚀 HƯỚNG DẪN LOGIN BẰNG AWS CLI (NO-KEY)"
echo "=================================================="
echo "👉 BƯỚC 1: Nếu terminal hiện tại từng dùng key cũ, hãy copy lệnh sau dán vào để xoá biến môi trường (Hoặc đơn giản là tắt mở lại tab terminal mới):"
echo "   unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE"
echo ""
echo "👉 BƯỚC 2: Mở trình duyệt, đăng nhập vào AWS Console và switch sang Role bạn cần dùng."
echo ""
echo "👉 BƯỚC 3: Quay lại Terminal và chạy lệnh:"
echo "   aws login"
echo "   (Ghi chú: Nếu báo lỗi command not found, thử dùng: aws sso login)"
echo ""
echo "👉 BƯỚC 4: Kiểm tra lại xem đăng nhập thành công chưa bằng lệnh:"
echo "   aws sts get-caller-identity"
echo "=================================================="
