#!/bin/bash

echo "🚀 BẮT ĐẦU CÀI ĐẶT AWS TOOLS..."

SECRET_FILE=$1
if [ -z "$SECRET_FILE" ] || [ ! -f "$SECRET_FILE" ]; then
    echo "❌ LỖI BẢO MẬT: Bạn chưa đính kèm file cấu hình bí mật (secret.txt)!"
    echo "👉 Hướng dẫn cài đặt đúng:"
    echo "   bash <(curl -sL \"https://raw.githubusercontent.com/thang-brian/aws-tool/refs/heads/master/install.sh\") /đường/dẫn/tới/secret.txt"
    exit 1
fi

# 1. Tạo thư mục chứa script
INSTALL_DIR="$HOME/scripts"
mkdir -p "$INSTALL_DIR"

# 1.5 Sao chép file secret vào nơi an toàn
mkdir -p "$HOME/.aws"
cp "$SECRET_FILE" "$HOME/.aws/aws-tools.env"
echo "✅ Đã nạp file cấu hình bảo mật thành công!"

# 2. Tải file nguyên khối (aws-tools.sh) từ Github
REPO_RAW_URL="https://raw.githubusercontent.com/thang-brian/aws-tool/refs/heads/master"
CACHE_BUST="?t=$(date +%s)"

echo "⬇️  Đang tải mã nguồn mới nhất..."
if command -v curl &> /dev/null; then
    curl -sL "$REPO_RAW_URL/aws-tools.sh${CACHE_BUST}" -o "$INSTALL_DIR/aws-tools.sh"
else
    echo "❌ Lỗi: Cần cài đặt lệnh 'curl' để có thể tải code từ Github!"
    exit 1
fi

chmod +x "$INSTALL_DIR/aws-tools.sh"

# 3. Tạo Alias trong Profile File (Đa nền tảng cho Mac/Zsh và Windows/Bash)
PROFILE_FILE="$HOME/.bashrc"
if [[ "$SHELL" == *"zsh"* ]] || [ -f "$HOME/.zshrc" ]; then
    PROFILE_FILE="$HOME/.zshrc"
elif [ -f "$HOME/.bash_profile" ]; then
    PROFILE_FILE="$HOME/.bash_profile"
fi

ALIAS_CMD="alias aws-tools='source $INSTALL_DIR/aws-tools.sh'"
ALIAS_LEGACY_CMD="alias aws-login='source $INSTALL_DIR/aws-tools.sh'"

# Xoá alias cũ (nếu có) và thêm alias mới
sed -i.bak '/alias aws-login=/d' "$PROFILE_FILE" 2>/dev/null
sed -i.bak '/alias aws-tools=/d' "$PROFILE_FILE" 2>/dev/null
rm -f "${PROFILE_FILE}.bak"

echo "$ALIAS_CMD" >> "$PROFILE_FILE"
echo "$ALIAS_LEGACY_CMD" >> "$PROFILE_FILE"

echo "✅ Cài đặt hoàn tất!"
echo "👉 Hãy chạy lệnh sau để tải cấu hình mới vào Terminal:"
echo "   source $PROFILE_FILE"
echo ""
echo "🔥 TỪ BÂY GIỜ, BẠN CÓ THỂ GÕ:"
echo "   aws-tools              : Để mở Bảng điều khiển"
echo "   aws-tools tunnel photo : Mở nhanh hầm DB photo"
echo "   aws-tools dbeaver photo: Lệnh dán vào DBeaver"
