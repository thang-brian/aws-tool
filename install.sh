#!/bin/bash

# === CẤU HÌNH GITHUB ===
REPO_RAW_URL="https://raw.githubusercontent.com/thang-brian/aws-tool/master"
# =======================

INSTALL_DIR="$HOME/scripts"

echo "🚀 Bắt đầu cài đặt/cập nhật AWS Tools..."

# 1. Tạo thư mục
mkdir -p "$INSTALL_DIR"
echo "📦 Đang kéo bản mới nhất từ Github vào: $INSTALL_DIR"

# 2. Tải các file cần thiết (chỉ dùng curl)
if command -v curl &> /dev/null; then
    CACHE_BUST="?t=$(date +%s)"
    curl -sL "$REPO_RAW_URL/aws-login.sh${CACHE_BUST}" -o "$INSTALL_DIR/aws-login.sh"
    curl -sL "$REPO_RAW_URL/db-tunnel.sh${CACHE_BUST}" -o "$INSTALL_DIR/db-tunnel.sh"
    curl -sL "$REPO_RAW_URL/ssh-bastion.sh${CACHE_BUST}" -o "$INSTALL_DIR/ssh-bastion.sh"
    curl -sL "$REPO_RAW_URL/updater.sh${CACHE_BUST}" -o "$INSTALL_DIR/updater.sh"
    curl -sL "$REPO_RAW_URL/version.txt${CACHE_BUST}" -o "$INSTALL_DIR/version.txt"
else
    echo "❌ Lỗi: Cần cài đặt lệnh 'curl' để có thể tải code từ Github!"
    exit 1
fi

# 3. Cấp quyền thực thi
chmod +x "$INSTALL_DIR/aws-login.sh"
chmod +x "$INSTALL_DIR/db-tunnel.sh"
chmod +x "$INSTALL_DIR/ssh-bastion.sh"
chmod +x "$INSTALL_DIR/updater.sh"

# 4. TỰ ĐỘNG QUÉT FILE CẤU HÌNH
TARGET_FILES=()
if [ -f "$HOME/.zshrc" ]; then TARGET_FILES+=("$HOME/.zshrc"); fi
if [ -f "$HOME/.bashrc" ]; then TARGET_FILES+=("$HOME/.bashrc"); fi
if [ -f "$HOME/.bash_profile" ]; then TARGET_FILES+=("$HOME/.bash_profile"); fi

if [ ${#TARGET_FILES[@]} -eq 0 ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        touch "$HOME/.zshrc"
        TARGET_FILES+=("$HOME/.zshrc")
    else
        touch "$HOME/.bashrc"
        TARGET_FILES+=("$HOME/.bashrc")
    fi
fi

# 5. Ghi cấu hình PATH vào file
for config_file in "${TARGET_FILES[@]}"; do
    echo "🔧 Đang cấu hình cho: $config_file"
    
    # Check: Thêm vào PATH (để không cần gõ ./)
    if grep -q "export PATH=\"$INSTALL_DIR:\$PATH\"" "$config_file"; then
        echo "   ✅ PATH đã tồn tại."
    else
        echo "" >> "$config_file"
        echo "# AWS Tools ACWORKS" >> "$config_file"
        echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$config_file"
        echo "   ➕ Đã thêm thư mục scripts vào PATH."
    fi

    # Thêm Alias để đảm bảo lệnh aws-login có thể xoá biến môi trường
    if grep -q "alias aws-login=" "$config_file"; then
        echo "   ✅ Alias aws-login đã tồn tại."
    else
        echo "alias aws-login='source $INSTALL_DIR/aws-login.sh'" >> "$config_file"
        echo "   ➕ Đã thêm lệnh rút gọn: aws-login"
    fi
    
    # Dọn dẹp source db_utils cũ (vì user đã xoá)
    # Dùng sed tương thích cho cả mac và linux
    if grep -q "source $INSTALL_DIR/db_utils.sh" "$config_file"; then
        sed -i.bak "\#source $INSTALL_DIR/db_utils.sh#d" "$config_file" 2>/dev/null || true
        rm -f "$config_file.bak" 2>/dev/null || true
        echo "   🧹 Đã dọn dẹp db_utils.sh cũ trong file cấu hình."
    fi
done

echo "------------------------------------------------"
echo "🎉 CÀI ĐẶT / UPDATE HOÀN TẤT!"
echo "👉 Hãy đảm bảo thay đổi biến REPO_RAW_URL trong install.sh thành link Github thực tế của bạn."
echo "👉 Bước cuối cùng: Hãy tắt terminal này và mở lại, hoặc gõ: source ~/.zshrc"
echo "------------------------------------------------"
