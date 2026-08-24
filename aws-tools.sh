#!/bin/bash
VERSION="2.2.3"
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
get_db_config() {
    local target=$1
    STATIC_PASS=""
    DB_USER=""
    TOKEN=""

    case $target in
        "illust")
            DB_HOST="$DB_HOST_ILLUST"
            DB_PORT="5432"
            LOCAL_PORT="5432"
            ;;
        "photo")
            DB_HOST="$DB_HOST_PHOTO"
            DB_PORT="3306"
            LOCAL_PORT="3306"
            ;;
        "common")
            DB_HOST="$DB_HOST_COMMON"
            DB_PORT="3306"
            LOCAL_PORT="3307"
            ;;
        "common_test")
            DB_HOST="$DB_HOST_COMMON_TEST"
            DB_PORT="3306"
            LOCAL_PORT="3308"
            STATIC_PASS="$COMMON_TEST_DB_PASS"
            ;;
        "newyear")
            DB_HOST="$DB_HOST_NEWYEAR"
            DB_PORT="3306"
            LOCAL_PORT="3309"
            STATIC_PASS="$NEWYEAR_DB_PASS"
            ;;
        *)
            echo "❌ Lỗi: Không tìm thấy DB '$target'"
            return 1 2>/dev/null || exit 1
            ;;
    esac
}

run_tunnel() {
    local target=$1
    get_db_config "$target" || return 1
    

    if [ -n "$STATIC_PASS" ]; then
        echo "⏳ Chế độ tĩnh: Đang lấy mật khẩu (không cần AWS Token)..."
        TOKEN="$STATIC_PASS"
    else
        CURRENT_USER=$(aws sts get-caller-identity --query Arn --output text --profile prod 2>/dev/null | awk -F/ '{print $NF}')
        if [ -z "$CURRENT_USER" ]; then
            echo "❌ Lỗi: Không lấy được IAM User. Bạn đã login chưa?"
            return 1 2>/dev/null || exit 1
        fi

        echo "⏳ Đang tạo Token đăng nhập DB cho user $CURRENT_USER..."
        TOKEN=$(aws rds generate-db-auth-token \
            --hostname "$DB_HOST" \
            --port "$DB_PORT" \
            --region "ap-northeast-1" \
            --username "$CURRENT_USER" \
            --profile prod 2>/dev/null)
    fi

    if [ -n "$TOKEN" ]; then
        echo -n "$TOKEN" | copy_to_clipboard
        echo "✅ Token đã được copy tự động vào Clipboard! (Nhấn Cmd+V / Ctrl+V để dán)"
    else
        echo "❌ Lỗi: Không tạo được Token. Vui lòng kiểm tra lại quyền IAM."
        return 1 2>/dev/null || exit 1
    fi

    echo "--------------------------------------------------"
    echo "⏳ Đang mở Port Forwarding tới DB: $target"
    echo "   📡 Bastion Host: $BASTION_ID"
    echo "   🔌 Target DB: $DB_HOST:$DB_PORT"
    echo "   💻 Local Port mở tại máy bạn: $LOCAL_PORT"
    echo "--------------------------------------------------"
    echo "⚠️  HẦM ĐÃ MỞ: Hãy giữ nguyên cửa sổ Terminal này để duy trì kết nối!"
    echo "👉 Dùng DBeaver/DataGrip kết nối vào localhost:$LOCAL_PORT và dán Token vào ô Password."
    echo "--------------------------------------------------"

    aws ssm start-session \
        --target "$BASTION_ID" \
        --document-name AWS-StartPortForwardingSessionToRemoteHost \
        --parameters "{\"host\":[\"$DB_HOST\"],\"portNumber\":[\"$DB_PORT\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}" \
        --profile prod
}

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
        DB_USER="$COMMON_TEST_DB_USER"
        if [ "$target" = "newyear" ]; then DB_USER="$NEWYEAR_DB_USER"; fi
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
        
        # Map to user's existing DBeaver connection names
        local dbeaver_name="${target}_Auto"
        case $target in
            "illust") dbeaver_name="illust New" ;;
            "photo") dbeaver_name="photo New" ;;
            "common") dbeaver_name="common Test New" ;;
            "common_test") dbeaver_name="common Test New" ;;
            "newyear") dbeaver_name="newyear New" ;;
        esac

        local driver="mysql8"
        local db_param=""
        if [ "$target" = "illust" ]; then 
            driver="postgres-jdbc"
            db_param="|database=acillustcom"
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
            eval "/Applications/DBeaver.app/Contents/MacOS/dbeaver $data_arg -con \"driver=$driver|name=$dbeaver_name|user=$DB_USER|password=$TOKEN${db_param}|create=false\"" &
        # Windows Git Bash
        elif command -v dbeaver-cli &> /dev/null; then
            dbeaver-cli -con "driver=$driver|name=$dbeaver_name|user=$DB_USER|password=$TOKEN${db_param}|create=false" &
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
    echo "1. Đăng nhập qua Web / SSO (Khuyên dùng - No Key)"
    echo "2. Đăng nhập qua MFA (Access Key cũ)"
    echo "--- KẾT NỐI SERVER & DB ---"
    echo "3. 🖥️  SSH vào Bastion Host (Giao diện CLI)"
    echo "4. 🛢️  Mở đường hầm (Tunnel) DB: Illust"
    echo "5. 🛢️  Tunnel -> Photo DB         (Port 3306)"
    echo "6. 🛢️  Tunnel -> Common DB        (Port 3307)"
    echo "7. 🛢️  Tunnel -> Common Test DB   (Port 3308)"
    echo "8. 🛢️  Tunnel -> NewYear DB       (Port 3309)"
    echo "9. 🚀 Auto-Connect DBeaver (Không cần Setup DBeaver)"
    echo "=================================================="
    printf "👉 Chọn [1-9]: "
    read MENU_CHOICE

    if [ "$MENU_CHOICE" = "1" ] || [ "$MENU_CHOICE" = "2" ]; then
        unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE
        CRED_FILE="$HOME/.aws/credentials"
        if [ -f "$CRED_FILE" ]; then
            cp "$CRED_FILE" "${CRED_FILE}.bak"
            sed -i.bak -e '/^[[:space:]]*$/! s/^\([^#]\)/# \1/' "$CRED_FILE"
            rm -f "${CRED_FILE}.bak"
        fi
    fi

    if [ "$MENU_CHOICE" = "1" ]; then
        echo "🌍 Đang khởi động trình duyệt để đăng nhập SSO..."
        aws login --profile base
        if [ $? -eq 0 ]; then
            echo "✅ Đăng nhập Web thành công!"
            aws sts get-caller-identity
        else
            echo "❌ Đăng nhập thất bại."
        fi
    elif [ "$MENU_CHOICE" = "2" ]; then
        # ... logic MFA rút gọn ...
        if [ -f "$CRED_FILE" ]; then
            sed -i.bak '/# \[japandev\]/,/^$/ s/^# //' "$CRED_FILE"
            rm -f "${CRED_FILE}.bak"
        fi
        echo "🔍 Kiểm tra MFA..."
        MFA_SERIAL=$(aws iam list-mfa-devices --profile japandev --output json 2>/dev/null | grep -o '"SerialNumber": "[^"]*' | cut -d'"' -f4)
        if [ -z "$MFA_SERIAL" ]; then echo "❌ Lỗi MFA."; return 1 2>/dev/null || exit 1; fi
        printf "👉 Nhập mã MFA (6 số): "
        read TOKEN_CODE
        CREDENTIALS_JSON=$(aws sts get-session-token --serial-number $MFA_SERIAL --token-code $TOKEN_CODE --profile japandev --duration-seconds 129600 --output json 2>/dev/null)
        if [ $? -ne 0 ]; then echo "❌ Xác thực thất bại!"; return 1 2>/dev/null || exit 1; fi
        aws configure set profile.mfa.aws_access_key_id $(echo $CREDENTIALS_JSON | grep -o '"AccessKeyId": "[^"]*' | cut -d'"' -f4)
        aws configure set profile.mfa.aws_secret_access_key $(echo $CREDENTIALS_JSON | grep -o '"SecretAccessKey": "[^"]*' | cut -d'"' -f4)
        aws configure set profile.mfa.aws_session_token $(echo $CREDENTIALS_JSON | grep -o '"SessionToken": "[^"]*' | cut -d'"' -f4)
        aws configure set profile.mfa.region ap-northeast-1
        export AWS_PROFILE=mfa
        echo "✅ Đã lưu phiên bản vào profile [mfa]!"
    elif [ "$MENU_CHOICE" = "3" ]; then
        echo "--------------------------------------------------"
        echo "💡 MẸO: Khi màn hình hiện chữ sh-4.2$, hãy gõ lệnh sau để lấy lại giao diện cũ:"
        echo "👉 sudo su - ec2-user"
        echo "--------------------------------------------------"
        aws ssm start-session --target "$BASTION_ID" --profile prod
    elif [[ "$MENU_CHOICE" -ge 4 && "$MENU_CHOICE" -le 8 ]]; then
        case $MENU_CHOICE in
            4) run_tunnel "illust" ;;
            5) run_tunnel "photo" ;;
            6) run_tunnel "common" ;;
            7) run_tunnel "common_test" ;;
            8) run_tunnel "newyear" ;;
        esac
    elif [ "$MENU_CHOICE" = "9" ]; then
        echo "Chọn DB muốn Auto-Connect:"
        echo "1) illust"
        echo "2) photo"
        echo "3) common"
        echo "4) common_test"
        echo "5) newyear"
        printf "👉 Chọn (1-5): "
        read DB_CHOICE
        case $DB_CHOICE in
            1) run_auto_dbeaver "illust" ;;
            2) run_auto_dbeaver "photo" ;;
            3) run_auto_dbeaver "common" ;;
            4) run_auto_dbeaver "common_test" ;;
            5) run_auto_dbeaver "newyear" ;;
            *) echo "❌ Không hợp lệ." ;;
        esac
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
