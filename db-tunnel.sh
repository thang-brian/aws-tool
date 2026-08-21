#!/bin/bash

# --- KIỂM TRA CẬP NHẬT TỰ ĐỘNG ---
if [ -f "$HOME/scripts/updater.sh" ]; then
    source "$HOME/scripts/updater.sh"
    check_for_updates
fi
# ---------------------------------

TARGET=$1
BASTION_ID="i-082dce83c6a043395"
PROFILE="default"

if [ -z "$TARGET" ]; then
    echo "❌ Lỗi: Bạn chưa chọn database."
    echo "👉 Cú pháp: db-tunnel.sh illust|photo|common"
    exit 1
fi

# 1. Kiểm tra session-manager-plugin
if ! command -v session-manager-plugin &> /dev/null; then
    echo "❌ Lỗi: Bạn chưa cài đặt Session Manager Plugin!"
    echo "👉 Vui lòng chạy lệnh sau để cài đặt (nhập mật khẩu máy Mac nếu được hỏi):"
    echo "   brew install --cask session-manager-plugin"
    exit 1
fi

# 2. Setup cấu hình tuỳ theo target
case $TARGET in
    "illust")
        DB_HOST="illustac-jp-aurora-cluster.cluster-ro-cyd4mntzeb3t.ap-northeast-1.rds.amazonaws.com"
        DB_PORT="5432"
        ;;
    "photo")
        DB_HOST="photoacdb.cyd4mntzeb3t.ap-northeast-1.rds.amazonaws.com"
        DB_PORT="3306"
        ;;
    "common")
        DB_HOST="commondb-prod.cyd4mntzeb3t.ap-northeast-1.rds.amazonaws.com"
        DB_PORT="3306"
        ;;
    "common_test")
        DB_HOST="commondb-test.cyd4mntzeb3t.ap-northeast-1.rds.amazonaws.com"
        DB_PORT="3306"
        ;;
    *)
        echo "❌ Lỗi: Không tìm thấy DB '$TARGET'"
        echo "👉 Các lựa chọn: illust, photo, common, common_test"
        exit 1
        ;;
esac

# 3. Mở tunnel
echo "--------------------------------------------------"
echo "⏳ Đang mở Port Forwarding tới DB: $TARGET"
echo "   📡 Bastion Host: $BASTION_ID"
echo "   🔌 Target DB: $DB_HOST:$DB_PORT"
echo "   💻 Local Port mở tại máy bạn: $DB_PORT"
echo "--------------------------------------------------"
echo "⚠️  Giữ nguyên cửa sổ Terminal này để duy trì kết nối!"
echo "👉 Dùng DBeaver/DataGrip kết nối vào localhost:$DB_PORT (Tắt SSH Tunnel trong app đi)"
echo "--------------------------------------------------"

aws ssm start-session \
    --target "$BASTION_ID" \
    --document-name AWS-StartPortForwardingSessionToRemoteHost \
    --parameters "{\"host\":[\"$DB_HOST\"],\"portNumber\":[\"$DB_PORT\"],\"localPortNumber\":[\"$DB_PORT\"]}"
