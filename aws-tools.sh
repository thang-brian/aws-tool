#!/bin/bash
VERSION="2.5.0"
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
        CURRENT_USER=$(aws sts get-caller-identity --query Arn --output text --profile base 2>/dev/null | awk -F/ '{print $NF}')
        TOKEN=$(aws rds generate-db-auth-token \
            --hostname "$DB_HOST" \
            --port "$DB_PORT" \
            --region "ap-northeast-1" \
            --username "$CURRENT_USER" \
            --profile base 2>/dev/null)
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
        CURRENT_USER=$(aws sts get-caller-identity --query Arn --output text --profile base 2>/dev/null | awk -F/ '{print $NF}')
        TOKEN=$(aws rds generate-db-auth-token \
            --hostname "$DB_HOST" \
            --port "$DB_PORT" \
            --region "ap-northeast-1" \
            --username "$CURRENT_USER" \
            --profile base 2>/dev/null)
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
        CURRENT_USER=$(aws sts get-caller-identity --query Arn --output text --profile base 2>/dev/null | awk -F/ '{print $NF}')
        DB_USER="$CURRENT_USER"
        TOKEN=$(aws rds generate-db-auth-token \
            --hostname "$DB_HOST" \
            --port "$DB_PORT" \
            --region "ap-northeast-1" \
            --username "$CURRENT_USER" \
            --profile base 2>/dev/null)
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
# ==========================================
# 4.1 SSH SERVERS & VS CODE MANAGER (CRUD)
# ==========================================
manage_ssh_servers() {
    python3 -c '
import json, os, sys, subprocess, re

ssh_servers_file = os.path.expanduser("~/.aws/ssh-servers.json")
bastion_id = os.environ.get("BASTION_ID", "i-082dce83c6a043395")

def load_servers():
    if not os.path.exists(ssh_servers_file):
        default_s = [
            {"name": "photo-ac-thang", "host": "172.30.6.197", "port": 2222, "user": "ec2-user", "switch_user": "git", "root": "/ebs1/photo-ac-thang", "key": "/Users/Shared/DB_Keys/newyear.pem"},
            {"name": "illust-ac-thang", "host": "172.30.6.81", "port": 2223, "user": "ec2-user", "switch_user": "git", "root": "/ebs1/projects/illust-ac-thang", "key": "/Users/Shared/DB_Keys/newyear.pem"}
        ]
        save_servers(default_s)
        return default_s
    try:
        with open(ssh_servers_file, "r") as f:
            return json.load(f)
    except:
        return []

def save_servers(servers):
    os.makedirs(os.path.dirname(ssh_servers_file), exist_ok=True)
    with open(ssh_servers_file, "w") as f:
        json.dump(servers, f, indent=2)
    sync_all(servers)

def sync_all(servers):
    # 1. Sync ~/.ssh/config
    ssh_config_file = os.path.expanduser("~/.ssh/config")
    if os.path.exists(ssh_config_file):
        with open(ssh_config_file, "r") as f:
            content = f.read()
        marker_start = "# --- MANAGED SSH SERVERS (START) ---"
        marker_end = "# --- MANAGED SSH SERVERS (END) ---"
        new_block_lines = [marker_start]
        for s in servers:
            new_block_lines.extend([
                f"Host {s["name"]}",
                f"  HostName {s["host"]}",
                f"  User {s.get("user", "ec2-user")}",
                f"  IdentityFile {s.get("key", "/Users/Shared/DB_Keys/newyear.pem")}",
                "  ProxyJump bastion",
                ""
            ])
        new_block_lines.append(marker_end)
        new_block = "\n".join(new_block_lines)
        if marker_start in content and marker_end in content:
            pattern = re.compile(rf"{re.escape(marker_start)}.*?{re.escape(marker_end)}", re.DOTALL)
            content = pattern.sub(new_block, content)
        else:
            content = content.strip() + "\n\n" + new_block + "\n"
        with open(ssh_config_file, "w") as f:
            f.write(content)

    # 2. Sync VS Code settings.json
    vscode_settings = os.path.expanduser("~/Library/Application Support/Code/User/settings.json")
    if os.path.exists(vscode_settings):
        try:
            with open(vscode_settings, "r") as f:
                v = json.load(f)
            v["sshfs.configs"] = [
                {
                    "name": s["name"],
                    "host": "127.0.0.1",
                    "port": s["port"],
                    "username": s.get("user", "ec2-user"),
                    "privateKeyPath": s.get("key", "/Users/Shared/DB_Keys/newyear.pem"),
                    "root": s.get("root", "/home/ec2-user")
                } for s in servers
            ]
            if "terminal.integrated.profiles.osx" not in v:
                v["terminal.integrated.profiles.osx"] = {"zsh": {"path": "zsh", "args": ["-l"]}}
            for s in servers:
                sw_cmd = f"cd {s.get("root", "/")} && sudo su {s.get("switch_user", "git")}"
                v["terminal.integrated.profiles.osx"][s["name"]] = {
                    "path": "ssh",
                    "args": ["-t", s["name"], sw_cmd],
                    "icon": "server"
                }
            with open(vscode_settings, "w") as f:
                json.dump(v, f, indent=2)
        except:
            pass

def get_next_port(servers):
    ports = [s.get("port", 2222) for s in servers]
    p = 2222
    while p in ports:
        p += 1
    return p

def start_tunnel(server):
    port = server["port"]
    host = server["host"]
    cmd = f"aws ssm start-session --target {bastion_id} --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters '''{{"host":["{host}"],"portNumber":["22"],"localPortNumber":["{port}"]}}''' --profile prod > /dev/null 2>&1 &"
    os.system(cmd)
    print(f"✅ Đã bật Tunnel ngầm cho {server["name"]} (127.0.0.1:{port})")

def menu():
    while True:
        servers = load_servers()
        print("\n==================================================")
        print("💻 QUẢN LÝ & KẾT NỐI SSH SERVER / VS CODE (CRUD)")
        print("==================================================")
        if not servers:
            print("  (Chưa có server nào được cấu hình)")
        else:
            for i, s in enumerate(servers, 1):
                print(f"  {i}) {s["name"]} -> IP: {s["host"]} | Folder: {s.get("root", "/")} | Port: {s.get("port", 2222)}")
        print("--------------------------------------------------")
        print("  a) ➕ Thêm Server mới (Create)")
        if servers:
            print("  e) ✏️  Sửa Server (Edit)")
            print("  d) 🗑️  Xóa Server (Delete)")
        print("  b) 🔙 Quay lại Menu chính")
        print("==================================================")
        choice = input("👉 Chọn (1-" + str(len(servers)) + " để kết nối, hoặc a/e/d/b): ").strip()
        
        if choice.lower() == "b":
            break
        elif choice.lower() == "a":
            name = input("👉 Nhập tên gợi nhớ (VD: photo-ac-thang): ").strip()
            if not name:
                print("❌ Tên không được để trống!")
                continue
            host = input("👉 Nhập IP nội bộ (VD: 172.30.6.197): ").strip()
            if not host:
                print("❌ IP không được để trống!")
                continue
            root = input("👉 Thư mục code từ xa [Enter để mặc định /home/ec2-user]: ").strip() or "/home/ec2-user"
            sw = input("👉 User chuyển quyền Terminal [Enter để mặc định git]: ").strip() or "git"
            usr = input("👉 User SSH kết nối [Enter để mặc định ec2-user]: ").strip() or "ec2-user"
            key = input("👉 Đường dẫn Private Key [Enter để mặc định /Users/Shared/DB_Keys/newyear.pem]: ").strip() or "/Users/Shared/DB_Keys/newyear.pem"
            port = get_next_port(servers)
            
            servers.append({
                "name": name,
                "host": host,
                "port": port,
                "user": usr,
                "switch_user": sw,
                "root": root,
                "key": key
            })
            save_servers(servers)
            print(f"✅ Đã thêm server [{name}] thành công!")
            print(f"✅ Đã tự động cập nhật ~/.ssh/config & VS Code!")
            start_tunnel(servers[-1])
        elif choice.lower() == "d" and servers:
            idx = input(f"👉 Nhập số thứ tự Server muốn xóa (1-{len(servers)}): ").strip()
            if idx.isdigit() and 1 <= int(idx) <= len(servers):
                deleted = servers.pop(int(idx)-1)
                save_servers(servers)
                print(f"🗑️ Đã xóa server [{deleted["name"]}] khỏi cấu hình!")
            else:
                print("❌ Số thứ tự không hợp lệ!")
        elif choice.lower() == "e" and servers:
            idx = input(f"👉 Nhập số thứ tự Server muốn sửa (1-{len(servers)}): ").strip()
            if idx.isdigit() and 1 <= int(idx) <= len(servers):
                s = servers[int(idx)-1]
                name = input(f"👉 Tên [{s["name"]}]: ").strip() or s["name"]
                host = input(f"👉 IP nội bộ [{s["host"]}]: ").strip() or s["host"]
                root = input(f"👉 Thư mục code [{s.get("root", "/")}]: ").strip() or s.get("root", "/")
                sw = input(f"👉 User chuyển quyền [{s.get("switch_user", "git")}]: ").strip() or s.get("switch_user", "git")
                key = input(f"👉 File Key [{s.get("key", "")}]: ").strip() or s.get("key", "")
                s["name"] = name
                s["host"] = host
                s["root"] = root
                s["switch_user"] = sw
                s["key"] = key
                save_servers(servers)
                print(f"✅ Đã cập nhật server [{name}] thành công!")
            else:
                print("❌ Số thứ tự không hợp lệ!")
        elif choice.isdigit() and 1 <= int(choice) <= len(servers):
            s = servers[int(choice)-1]
            print(f"\n--- THAO TÁC VỚI [{s["name"]}] ---")
            print("1. 🖥️  Mở Terminal SSH (user " + s.get("switch_user", "git") + ")")
            print("2. 🛢️  Mở đường hầm Tunnel (Port " + str(s["port"]) + " cho VS Code SSH FS)")
            act = input("👉 Chọn [1-2]: ").strip()
            if act == "1":
                start_tunnel(s)
                sw_cmd = f"cd {s.get("root", "/")} && sudo su {s.get("switch_user", "git")}"
                os.system(f"ssh -t {s["name"]} "{sw_cmd}"")
            elif act == "2":
                start_tunnel(s)
        else:
            print("❌ Lựa chọn không hợp lệ!")

menu()
'
}

run_menu() {
    echo "=================================================="
    echo "🚀 BẢNG ĐIỀU KHIỂN TRUNG TÂM (AWS TOOLS) v$VERSION"
    echo "=================================================="
    echo "--- ĐĂNG NHẬP ---"
    echo "1. Đăng nhập qua Web / SSO (All in-One - Loại bỏ cơ chế Access keys)"
    echo "👉 Lần sử dụng tool đầu tiên: rm -rf ~/.aws/login/cache/*"
    echo "👉 Switch back role đang dùng ở web về lại default"
    echo "--- KẾT NỐI SERVER & DB ---"
    echo "2. 🖥️  SSH vào Bastion Host (Giao diện CLI)"
    echo "3. 🛢️  Mở đường hầm (Tunnel) thủ công tới Database"
    echo "4. 🚀 Auto-Connect DBeaver (Không cần Setup DBeaver)"
    echo "5. 💻 Quản lý & Kết nối SSH Server / VS Code (CRUD)"
    echo "=================================================="
    printf "👉 Chọn [1-5]: "
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
        echo "⏳ Đang kết nối tới Bastion..."
        python3 -c '
import pty, os, sys, select, signal, fcntl, termios, tty

def sync_win_size(fd):
    try:
        # Lấy kích thước cửa sổ hiện tại của terminal và gán sang pty
        size = fcntl.ioctl(sys.stdin.fileno(), termios.TIOCGWINSZ, b"\0" * 8)
        fcntl.ioctl(fd, termios.TIOCSWINSZ, size)
    except Exception:
        pass

pid, fd = pty.fork()
if pid == 0:
    os.execvp("aws", ["aws", "ssm", "start-session", "--target", "'"$BASTION_ID"'", "--profile", "prod"])

# Đồng bộ size ngay lúc khởi tạo và mỗi khi resize cửa sổ
sync_win_size(fd)
signal.signal(signal.SIGWINCH, lambda signum, frame: sync_win_size(fd))

switched = False
old_settings = termios.tcgetattr(sys.stdin)
tty.setraw(sys.stdin)

try:
    while True:
        r, _, _ = select.select([sys.stdin, fd], [], [])
        if sys.stdin in r:
            data = os.read(sys.stdin.fileno(), 1024)
            if not data: break
            os.write(fd, data)
        if fd in r:
            data = os.read(fd, 1024)
            if not data: break
            os.write(sys.stdout.fileno(), data)
            sys.stdout.flush()
            if not switched and (b"sh-4.2$" in data or b"$ " in data):
                os.write(fd, b"sudo su - ec2-user\n")
                switched = True
finally:
    termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_settings)
'
    elif [ "$MENU_CHOICE" = "3" ] || [ "$MENU_CHOICE" = "4" ]; then
        if [ "$MENU_CHOICE" = "3" ]; then
            echo "Chọn DB muốn mở Tunnel thủ công:"
        else
            echo "Chọn DB muốn Auto-Connect:"
        fi
        
        local j=1
        for key in "${DB_KEYS[@]}"; do
            local display_name=$(echo "$key" | tr 'A-Z' 'a-z')
            eval "local port=\"\$LOCAL_PORT_$key\""
            if [ -z "$port" ]; then port="3306"; fi
            echo "$j) $display_name (Port $port)"
            j=$((j+1))
        done
        printf "👉 Chọn (1-$((j-1))): "
        read DB_CHOICE
        
        if [[ "$DB_CHOICE" -ge 1 && "$DB_CHOICE" -lt $j ]]; then
            local current_j=1
            for key in "${DB_KEYS[@]}"; do
                if [ "$current_j" -eq "$DB_CHOICE" ]; then
                    local target=$(echo "$key" | tr 'A-Z' 'a-z')
                    if [ "$MENU_CHOICE" = "3" ]; then
                        run_tunnel "$target"
                    else
                        run_auto_dbeaver "$target"
                    fi
                    break
                fi
                current_j=$((current_j+1))
            done
        else
            echo "❌ Lựa chọn không hợp lệ."
        fi
    elif [ "$MENU_CHOICE" = "5" ]; then
        manage_ssh_servers
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
    "ssh-server"|"server") manage_ssh_servers ;;
    *) 
        setup_aws_config
        run_menu 
        ;;
esac