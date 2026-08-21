#!/bin/bash

# --- KIỂM TRA CẬP NHẬT TỰ ĐỘNG ---
if [ -f "$HOME/scripts/updater.sh" ]; then
    source "$HOME/scripts/updater.sh"
    check_for_updates
fi
# ---------------------------------

PEM_PATH=$1
BASTION_ID="i-082dce83c6a043395"
SSH_CONFIG="$HOME/.ssh/config"

echo "🛠️ Bắt đầu cấu hình SSH Bastion Host..."

if [ -z "$PEM_PATH" ]; then
    echo "❌ Lỗi: Bạn chưa cung cấp đường dẫn tới file .pem"
    echo "👉 Cú pháp: ssh-bastion.sh /duong/dan/toi/file.pem"
    exit 1
fi

if [ ! -f "$PEM_PATH" ]; then
    echo "❌ Lỗi: Không tìm thấy file $PEM_PATH"
    exit 1
fi

# Chuyển thành đường dẫn tuyệt đối để ghi vào file config cho chắc
ABS_PEM_PATH=$(realpath "$PEM_PATH")

mkdir -p "$HOME/.ssh"
touch "$SSH_CONFIG"

# Kiểm tra xem đã có cấu hình bastionhost chưa
if grep -q "Host bastionhost" "$SSH_CONFIG"; then
    echo "⚠️ Trong file ~/.ssh/config đã tồn tại cấu hình 'Host bastionhost'."
    echo "👉 Vui lòng mở file ra và tự kiểm tra/chỉnh sửa bằng tay (lệnh: vi ~/.ssh/config)"
    exit 0
fi

# Ghi cấu hình vào file
cat <<EOF >> "$SSH_CONFIG"

Host bastionhost
  HostName $BASTION_ID
  User ec2-user
  IdentityFile "$ABS_PEM_PATH"
  ProxyCommand sh -c "aws ssm start-session --target %h --region ap-northeast-1 --document-name AWS-StartSSHSession --parameters 'portNumber=%p'"
EOF

echo "✅ Đã thêm cấu hình thành công vào ~/.ssh/config"
echo "------------------------------------------------"
echo "🚀 Từ bây giờ, để SSH vào Bastion Host, bạn chỉ cần gõ:"
echo "   ssh bastionhost"
echo "------------------------------------------------"
