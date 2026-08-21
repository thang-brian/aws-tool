#!/bin/bash

# === CẤU HÌNH GITHUB ===
REPO_RAW_URL="https://raw.githubusercontent.com/thang-brian/aws-tool/master"
# =======================

check_for_updates() {
    local install_dir="$HOME/scripts"
    local local_version_file="$install_dir/version.txt"
    
    # Nếu chưa có file version local thì tạo mặc định
    if [ ! -f "$local_version_file" ]; then
        echo "1.0.0" > "$local_version_file"
    fi
    
    local current_version=$(cat "$local_version_file" 2>/dev/null)
    
    # Dùng curl để lấy version mới nhất, timeout 2s để không làm chậm lúc user login
    if command -v curl &> /dev/null; then
        local latest_version=$(curl -s --max-time 2 "$REPO_RAW_URL/version.txt")
        
        # Kiểm tra xem curl có trả về kết quả hợp lệ không (có format x.y.z)
        if [[ ! -z "$latest_version" && "$latest_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            if [ "$latest_version" != "$current_version" ]; then
                echo -e "\n🚀 Phát hiện phiên bản mới: v$latest_version (Hiện tại: v$current_version)"
                echo "⏳ Đang tự động cập nhật, xin chờ trong giây lát..."
                
                # Tải file install.sh từ Github và thực thi nó
                curl -sL "$REPO_RAW_URL/install.sh" | bash
                
                if [ $? -eq 0 ]; then
                    echo "✅ Đã cập nhật xong! Hãy chạy lại lệnh vừa rồi."
                    exit 0
                else
                    echo "❌ Lỗi: Cập nhật thất bại. Vẫn tiếp tục chạy bản cũ..."
                fi
            fi
        fi
    fi
}
