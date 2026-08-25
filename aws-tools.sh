#!/bin/bash
VERSION="2.3.2"
REPO_RAW_URL="https://raw.githubusercontent.com/thang-brian/aws-tool/refs/heads/master"

if [ -f "$HOME/.aws/aws-tools.env" ]; then
    source "$HOME/.aws/aws-tools.env"
fi

# ==========================================
# 0. CROSS-PLATFORM UTILITIES
# ==========================================
copy_to_clipboard() {
    if command -v pbcopy &> /dev/null; then
        pbcopy
    elif command -v clip.exe &> /dev/null; then
        clip.exe
    elif command -v clip &> /dev/null; then
        clip
    else
        cat > /dev/null
    fi
}

is_port_in_use() {
    local port=$1
    if command -v lsof &> /dev/null; then
        lsof -i:$port -t >/dev/null 2>&1
    elif command -v netstat.exe &> /dev/null; then
        netstat.exe -ano | grep -E ":$port\s" >/dev/null 2>&1
    elif command -v netstat &> /dev/null; then
        netstat -ano | grep -E ":$port\s" >/dev/null 2>&1
    else
        return 1 # Fallback, assume not in use
    fi
}

# ==========================================
# 1. AUTO-UPDATER
# ==========================================
check_for_updates() {
    local CACHE_BUST="?t=$(date +%s)"
    local REMOTE_VERSION=$(curl -sL "$REPO_RAW_URL/aws-tools.sh${CACHE_BUST}" | grep '^VERSION=' | cut -d'"' -f2)
    
    if [ -n "$REMOTE_VERSION" ] && [ "$REMOTE_VERSION" != "$VERSION" ]; then
        echo "🔄 Phát hiện phiên bản mới: v$REMOTE_VERSION (Hiện tại: v$VERSION)"
        echo "⬇️  Đang tự động cập nhật..."
        curl -sL "$REPO_RAW_URL/aws-tools.sh${CACHE_BUST}" -o "$HOME/scripts/aws-tools.sh"
        chmod +x "$HOME/scripts/aws-tools.sh"
        echo "✅ Cập nhật thành công! Đang khởi động lại tool..."
        source "$HOME/scripts/aws-tools.sh" "$@"
        return 99 2>/dev/null || exit 99
    fi
}

# ==========================================
# 2. AUTO-CONFIG SETUP
# ==========================================
setup_aws_config() {
    local config_file="$HOME/.aws/config"
    local env_file="$HOME/.aws/aws-tools.env"
    
    if [ ! -f "$env_file" ]; then
        echo "❌ Lỗi: Không tìm thấy file cấu hình bảo mật (~/.aws/aws-tools.env)."
        echo "Vui lòng cài đặt lại kèm file secret.txt!"
        return 1 2>/dev/null || exit 1
    fi
    source "$env_file"

    if ! grep -q "\[profile prod\]" "$config_file" 2>/dev/null; then
        echo "=================================================="
        echo "⚙️  TỰ ĐỘNG KHỞI TẠO CẤU HÌNH AWS LẦN ĐẦU..."
        echo "=================================================="
        printf "👉 Nhập User ARN của bạn (VD: arn:aws:iam::123456789:user/user): "
        read IAM_USER_ARN
        
        if [ -z "$IAM_USER_ARN" ]; then
            echo "❌ Cần User ARN để tiếp tục."
            return 1 2>/dev/null || exit 1
        fi
        
        # Tự động sửa lỗi nếu người dùng nhập nhầm chuỗi STS Assumed Role (copy từ góc phải AWS Console)
        if [[ "$IAM_USER_ARN" == *"sts"* ]] || [[ "$IAM_USER_ARN" == *"assumed-role"* ]]; then
            local ACCOUNT_ID=$(echo "$IAM_USER_ARN" | awk -F':' '{print $5}')
            local USERNAME=$(echo "$IAM_USER_ARN" | awk -F'/' '{print $NF}')
            IAM_USER_ARN="arn:aws:iam::${ACCOUNT_ID}:user/${USERNAME}"
            echo "⚠️  Phát hiện nhập nhầm STS Role. Đã tự động sửa thành: $IAM_USER_ARN"
        fi
        
        local ARN_PREFIX=$(echo "$IAM_USER_ARN" | awk -F'user/' '{print $1}')
        local IAM_USER=$(echo "$IAM_USER_ARN" | awk -F'user/' '{print $2}')
        local DEV_ROLE="${ARN_PREFIX}role/${DEV_ROLE_NAME}"
        local PROD_ROLE="${ARN_PREFIX}role/${PROD_ROLE_NAME}"
        
        mkdir -p "$HOME/.aws"
        
        if [ -f "$config_file" ]; then
            local bk_file="${config_file}_bk_$(date +%Y%m%d_%H%M%S)"
            cp "$config_file" "$bk_file"
            echo "📁 Đã backup file cấu hình cũ sang: $bk_file"
        fi
        
        cat <<EOF_CONFIG > "$config_file"
[profile base]
region = ap-northeast-1
login_session = $IAM_USER_ARN

[default]
source_profile = base
role_arn = $DEV_ROLE
role_session_name = $IAM_USER
region = ap-northeast-1

[profile prod]
source_profile = base
role_arn = $PROD_ROLE
role_session_name = $IAM_USER
region = ap-northeast-1

[profile mfa]
region = ap-northeast-1
EOF_CONFIG
        echo "✅ Khởi tạo cấu hình AWS thành công!"
        echo "=================================================="
    fi
}

# ==========================================
# 3. DB TUNNEL & DBEAVER CONNECT LOGIC
# ==========================================
# ==========================================
# DYNAMIC DB DISCOVERY
# ==========================================
if [ -n "$ZSH_VERSION" ]; then
    DB_KEYS=($(set | grep "^DB_HOST_" | awk -F'=' '{print $1}' | sed 's/DB_HOST_//'))
else
    DB_KEYS=($(env | grep "^DB_HOST_" | awk -F'=' '{print $1}' | sed 's/DB_HOST_//'))
    if [ ${#DB_KEYS[@]} -eq 0 ]; then
        DB_KEYS=($(set | grep "^DB_HOST_" | awk -F'=' '{print $1}' | sed 's/DB_HOST_//'))
    fi
fi

get_db_config() {
    local target=$(echo "$1" | tr 'a-z' 'A-Z')
    STATIC_PASS=""
    STATIC_USER=""
    DB_USER=""
    TOKEN=""
    
    eval "DB_HOST=\"\$DB_HOST_$target\""
    eval "DB_PORT=\"\$DB_PORT_$target\""
    eval "LOCAL_PORT=\"\$LOCAL_PORT_$target\""
    eval "STATIC_USER=\"\$DB_USER_$target\""
    eval "STATIC_PASS=\"\$DB_PASS_$target\""
    eval "DB_DRIVER=\"\$DB_DRIVER_$target\""
    eval "DB_NAME=\"\$DB_NAME_$target\""
    eval "DBEAVER_NAME=\"\$DBEAVER_NAME_$target\""

    if [ -z "$DB_PORT" ]; then DB_PORT="3306"; fi
    if [ -z "$LOCAL_PORT" ]; then LOCAL_PORT="3306"; fi
    if [ -z "$DB_DRIVER" ]; then DB_DRIVER="mysql8"; fi
    if [ -z "$DBEAVER_NAME" ]; then DBEAVER_NAME="${1}_Auto"; fi

    if [ -z "$DB_HOST" ]; then
        echo "❌ Lỗi: Không tìm thấy DB_HOST_$target trong cấu hình!"
        return 1 2>/dev/null || exit 1
    fi
}

# ==========================================
# 3. TUNNEL BASTION
# ==========================================
run_tunnel() {
    local target=$1
    export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH
    get_db_config "$target" || return 1
    
    if is_port_in_use "$LOCAL_PORT"; then
        echo "❌ Lỗi: Cổng $LOCAL_PORT đang được sử dụng. Vui lòng tắt tiến trình hoặc đóng Tunnel cũ trước."
        return 1 2>/dev/null || exit 1
    fi

    if [ -n "$STATIC_PASS" ]; then
        TOKEN="$STATIC_PASS"
        if [ -n "$STATIC_USER" ]; then DB_USER="$STATIC_USER"; fi
        echo "✅ Lấy mật khẩu tĩnh thành công!"
    else
        CURRENT_USER=$(aws sts get-caller-identity --query Arn --output text --profile prod 2>/dev/null | awk -F/ '{print $NF}')
        TOKEN=$(aws rds generate-db-auth-token \
            --hostname "$DB_HOST" \
            --port "$DB_PORT" \
            --region "ap-northeast-1" \
            --username "$CURRENT_USER" \
            --profile prod 2>/dev/null)
    fi

    if [ -n "$TOKEN" ]; then
        echo -n "$TOKEN" | copy_to_clipboard
        if [ -n "$STATIC_PASS" ]; then
            echo "✅ Mật khẩu đã copy vào Clipboard!"
        else
            echo "✅ Token đã copy vào Clipboard! (User: $CURRENT_USER)"
        fi
    else
        echo "❌ Lỗi: Không lấy được DB Token!"
        return 1 2>/dev/null || exit 1
    fi

    echo "⏳ Đang mở đường hầm (Port Forwarding) qua Bastion tới $target..."
    echo "🔑 Local Port: $LOCAL_PORT -> Remote Port: $DB_PORT"
    aws ssm start-session \
        --target "$BASTION_ID" \
        --document-name AWS-StartPortForwardingSessionToRemoteHost \
        --parameters "{\"host\":[\"$DB_HOST\"],\"portNumber\":[\"$DB_PORT\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}" \
        --profile prod > /dev/null 2>&1 &
    
    sleep 2
    echo "✅ Tunnel đã chạy ngầm thành công! Bạn có thể tiếp tục dùng Tab này."
}

# ==========================================
# 3.1 DBeaver TOKEN GENERATOR
# ==========================================
run_dbeaver() {
    local target=$1
    export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH
    get_db_config "$target" || return 1
    
    if ! is_port_in_use "$LOCAL_PORT"; then
        echo "⏳ Tunnel chưa mở! Đang tự động mở ngầm Port Forwarding tới $target..."
        aws ssm start-session \
            --target "$BASTION_ID" \
            --document-name AWS-StartPortForwardingSessionToRemoteHost \
            --parameters "{\"host\":[\"$DB_HOST\"],\"portNumber\":[\"$DB_PORT\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}" \
            --profile prod > /dev/null 2>&1 &
        sleep 3
    fi

    if [ -n "$STATIC_PASS" ]; then
        TOKEN="$STATIC_PASS"
        if [ -n "$STATIC_USER" ]; then DB_USER="$STATIC_USER"; fi
        echo "✅ Lấy mật khẩu tĩnh thành công!"
    else
        CURRENT_USER=$(aws sts get-caller-identity --query Arn --output text --profile prod 2>/dev/null | awk -F/ '{print $NF}')
        TOKEN=$(aws rds generate-db-auth-token \
            --hostname "$DB_HOST" \
            --port "$DB_PORT" \
            --region "ap-northeast-1" \
            --username "$CURRENT_USER" \
            --profile prod 2>/dev/null)
    fi

    if [ -n "$TOKEN" ]; then
        echo -n "$TOKEN" | copy_to_clipboard
        if [ -n "$STATIC_PASS" ]; then
            echo "✅ Tunnel đã mở & Mật khẩu đã copy vào Clipboard!"
        else
            echo "✅ Tunnel đã mở & Token đã copy vào Clipboard! (User: $CURRENT_USER)"
        fi
    else
        echo "❌ Lỗi: Không lấy được DB Token!"
        return 1 2>/dev/null || exit 1
    fi
}

# ==========================================
# 3.5 AUTO DBEAVER (ZERO-CONFIG CLI)
# ==========================================
run_auto_dbeaver() {
    local target=$1
    export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH
    get_db_config "$target" || return 1
    
    if ! is_port_in_use "$LOCAL_PORT"; then
        echo "⏳ Tunnel chưa mở! Đang tự động mở ngầm Port Forwarding tới $target..."
        aws ssm start-session \
            --target "$BASTION_ID" \
            --document-name AWS-StartPortForwardingSessionToRemoteHost \
            --parameters "{\"host\":[\"$DB_HOST\"],\"portNumber\":[\"$DB_PORT\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}" \
            --profile prod > /dev/null 2>&1 &
        sleep 3
    fi

    if [ -n "$STATIC_PASS" ]; then
        TOKEN="$STATIC_PASS"
        if [ -n "$STATIC_USER" ]; then DB_USER="$STATIC_USER"; fi
        echo "✅ Lấy mật khẩu tĩnh thành công!"
    else
        CURRENT_USER=$(aws sts get-caller-identity --query Arn --output text --profile prod 2>/dev/null | awk -F/ '{print $NF}')
        DB_USER="$CURRENT_USER"
        TOKEN=$(aws rds generate-db-auth-token \
            --hostname "$DB_HOST" \
            --port "$DB_PORT" \
            --region "ap-northeast-1" \
            --username "$CURRENT_USER" \
            --profile prod 2>/dev/null)
        echo "✅ Sinh IAM Token thành công!"
    fi

    if [ -n "$TOKEN" ]; then
        echo "🚀 Đang gọi DBeaver mở Database $target..."
        
        local db_param=""
        if [ -n "$DB_NAME" ]; then 
            db_param="|database=$DB_NAME"
        fi
        
        # MacOS
        if [ -d "/Applications/DBeaver.app" ]; then
            local data_arg=""
            if [ -f "$HOME/Library/DBeaverData/.workspaces" ]; then
                local workspace_path=$(head -n 1 "$HOME/Library/DBeaverData/.workspaces")
                if [ -n "$workspace_path" ] && [ -d "$workspace_path" ]; then
                    data_arg="-data \"$workspace_path\""
                fi
            fi
            # Use create=false so it reuses the existing connection and its SSL config
            eval "/Applications/DBeaver.app/Contents/MacOS/dbeaver $data_arg -con \"driver=$DB_DRIVER|name=$DBEAVER_NAME|user=$DB_USER|password=$TOKEN${db_param}|create=false\"" &
        # Windows Git Bash
        elif command -v dbeaver-cli &> /dev/null; then
            dbeaver-cli -con "driver=$DB_DRIVER|name=$DBEAVER_NAME|user=$DB_USER|password=$TOKEN${db_param}|create=false" &
        else
            echo "❌ Lỗi: Không tìm thấy DBeaver trên máy."
        fi
    else
        echo "❌ Lỗi: Không lấy được DB Token!"
        return 1 2>/dev/null || exit 1
    fi
}

# ==========================================
# 4. BASTION SSH (FALLBACK)
# ==========================================
run_ssh_bastion() {
    local PEM_FILE=$1
    if [ -z "$PEM_FILE" ]; then
        echo "❌ Lỗi: Bạn chưa cung cấp đường dẫn tới file .pem"
        echo "👉 Sử dụng: aws-tools ssh /path/to/key.pem"
        return 1 2>/dev/null || exit 1
    fi

    echo "⏳ Đang kết nối SSH tới Bastion qua đường hầm SSM..."
    ssh -i "$PEM_FILE" ec2-user@$BASTION_ID \
        -o ProxyCommand="aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters 'portNumber=%p' --profile prod"
}

# ==========================================
# 5. MAIN MENU
# ==========================================
run_menu() {
    echo "=================================================="
    echo "🚀 BẢNG ĐIỀU KHIỂN TRUNG TÂM (AWS TOOLS) v$VERSION"
    echo "=================================================="
    echo "--- ĐĂNG NHẬP ---"
    echo "1. Đăng nhập qua Web / SSO (All in-One - Loại bỏ cơ chế Access keys)"
    echo "👉 Lần sử dụng tool đầu tiên: rm -rf ~/.aws/login/cache/*"
    echo "--- KẾT NỐI SERVER & DB ---"
    echo "2. 🖥️  SSH vào Bastion Host (Giao diện CLI)"
    
    local i=3
    # Danh sách Tunnel động
    for key in "${DB_KEYS[@]}"; do
        eval "local port=\"\$LOCAL_PORT_$key\""
        if [ -z "$port" ]; then port="3306"; fi
        local display_name=$(echo "$key" | tr 'A-Z' 'a-z')
        echo "$i. 🛢️  Tunnel -> $display_name DB (Port $port)"
        i=$((i+1))
    done

    local auto_option=$i
    echo "$auto_option. 🚀 Auto-Connect DBeaver (Không cần Setup DBeaver)"
    echo "=================================================="
    printf "👉 Chọn [1-$auto_option]: "
    read MENU_CHOICE

    if [ "$MENU_CHOICE" = "1" ]; then
        unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE
        CRED_FILE="$HOME/.aws/credentials"
        if [ -f "$CRED_FILE" ]; then
            mv "$CRED_FILE" "${CRED_FILE}_bk_$(date +%Y%m%d_%H%M%S)"
            echo "🗑️  Đã vô hiệu hóa file credentials cũ (chuyển thành credentials_bk) để an toàn 100%!"
        fi
        
        echo "🌍 Đang khởi động trình duyệt để đăng nhập SSO..."
        aws login --profile base
        if [ $? -eq 0 ]; then
            echo "✅ Đăng nhập Web thành công!"
            aws sts get-caller-identity
        else
            echo "❌ Đăng nhập thất bại."
        fi
    elif [ "$MENU_CHOICE" = "2" ]; then
        echo "--------------------------------------------------"
        echo "💡 MẸO: Khi màn hình hiện chữ sh-4.2$, hãy gõ lệnh sau để lấy lại giao diện cũ:"
        echo "👉 sudo su - ec2-user"
        echo "--------------------------------------------------"
        aws ssm start-session --target "$BASTION_ID" --profile prod
    elif [[ "$MENU_CHOICE" -ge 3 && "$MENU_CHOICE" -lt $auto_option ]]; then
        local current_i=3
        for key in "${DB_KEYS[@]}"; do
            if [ "$current_i" -eq "$MENU_CHOICE" ]; then
                local target=$(echo "$key" | tr 'A-Z' 'a-z')
                run_tunnel "$target"
                break
            fi
            current_i=$((current_i+1))
        done
    elif [ "$MENU_CHOICE" = "$auto_option" ]; then
        echo "Chọn DB muốn Auto-Connect:"
        local j=1
        for key in "${DB_KEYS[@]}"; do
            local display_name=$(echo "$key" | tr 'A-Z' 'a-z')
            echo "$j) $display_name"
            j=$((j+1))
        done
        printf "👉 Chọn (1-$((j-1))): "
        read DB_CHOICE
        
        if [[ "$DB_CHOICE" -ge 1 && "$DB_CHOICE" -lt $j ]]; then
            local current_j=1
            for key in "${DB_KEYS[@]}"; do
                if [ "$current_j" -eq "$DB_CHOICE" ]; then
                    local target=$(echo "$key" | tr 'A-Z' 'a-z')
                    run_auto_dbeaver "$target"
                    break
                fi
                current_j=$((current_j+1))
            done
        else
            echo "❌ Không hợp lệ."
        fi
    else
        echo "❌ Không hợp lệ."
    fi
}

# ==========================================
# ROUTER
# ==========================================
check_for_updates
if [ $? -eq 99 ]; then return 0 2>/dev/null || exit 0; fi

case "$1" in
    "tunnel") run_tunnel "$2" ;;
    "dbeaver") run_dbeaver "$2" ;;
    "ssh") run_ssh_bastion "$2" ;;
    *) 
        setup_aws_config
        run_menu 
        ;;
esac
