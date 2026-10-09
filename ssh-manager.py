#!/usr/bin/env python3
import json
import os
import sys
import subprocess
import re

SSH_SERVERS_FILE = os.path.expanduser("~/.aws/ssh-servers.json")
SSH_CONFIG_FILE = os.path.expanduser("~/.ssh/config")
VSCODE_SETTINGS_FILE = os.path.expanduser("~/Library/Application Support/Code/User/settings.json")

def safe_input(prompt=""):
    try:
        return input(prompt).strip()
    except (KeyboardInterrupt, EOFError):
        return None

def get_bastion_id():
    b_id = os.environ.get("BASTION_ID", "")
    if not b_id:
        env_file = os.path.expanduser("~/.aws/aws-tools.env")
        if os.path.exists(env_file):
            try:
                with open(env_file) as f:
                    for line in f:
                        if line.startswith("BASTION_ID="):
                            b_id = line.split("=", 1)[1].strip().strip('"').strip("'")
                            break
            except Exception:
                pass
    return b_id

def load_servers():
    if not os.path.exists(SSH_SERVERS_FILE):
        return []
    try:
        with open(SSH_SERVERS_FILE, "r") as f:
            return json.load(f)
    except Exception:
        return []

def save_servers(servers):
    os.makedirs(os.path.dirname(SSH_SERVERS_FILE), exist_ok=True)
    with open(SSH_SERVERS_FILE, "w") as f:
        json.dump(servers, f, indent=2)
    sync_all(servers)

def sync_all(servers):
    sync_ssh_config(servers)
    sync_vscode(servers)

def sync_ssh_config(servers):
    if not os.path.exists(SSH_CONFIG_FILE):
        return
    try:
        with open(SSH_CONFIG_FILE, "r") as f:
            content = f.read()

        marker_start = "# --- MANAGED SSH SERVERS (START) ---"
        marker_end = "# --- MANAGED SSH SERVERS (END) ---"

        new_block_lines = [marker_start]
        for s in servers:
            key_line = f"  IdentityFile {s['key']}" if s.get("key") else ""
            lines = [
                f"Host {s['name']}",
                f"  HostName {s['host']}",
                f"  User {s.get('user', 'ec2-user')}",
            ]
            if key_line:
                lines.append(key_line)
            lines.extend([
                "  ProxyJump bastion",
                ""
            ])
            new_block_lines.extend(lines)
        new_block_lines.append(marker_end)
        new_block = "\n".join(new_block_lines)

        if marker_start in content and marker_end in content:
            pattern = re.compile(rf"{re.escape(marker_start)}.*?{re.escape(marker_end)}", re.DOTALL)
            content = pattern.sub(new_block, content)
        else:
            content = content.strip() + "\n\n" + new_block + "\n"

        with open(SSH_CONFIG_FILE, "w") as f:
            f.write(content)
    except Exception as e:
        print("Lỗi đồng bộ ~/.ssh/config:", e)

def sync_vscode(servers):
    if not os.path.exists(VSCODE_SETTINGS_FILE):
        return
    try:
        with open(VSCODE_SETTINGS_FILE, "r") as f:
            v = json.load(f)

        v["sshfs.configs"] = [
            {
                "name": s["name"],
                "host": "127.0.0.1",
                "port": s["port"],
                "username": s.get("user", "ec2-user"),
                "privateKeyPath": s.get("key", ""),
                "root": s.get("root", "/home/ec2-user")
            } for s in servers
        ]

        if "terminal.integrated.profiles.osx" not in v:
            v["terminal.integrated.profiles.osx"] = {"zsh": {"path": "zsh", "args": ["-l"]}}

        for s in servers:
            sw_cmd = f"cd {s.get('root', '/')} && sudo su {s.get('switch_user', 'git')}"
            v["terminal.integrated.profiles.osx"][s["name"]] = {
                "path": "ssh",
                "args": ["-t", s["name"], sw_cmd],
                "icon": "server"
            }

        with open(VSCODE_SETTINGS_FILE, "w") as f:
            json.dump(v, f, indent=2)
    except Exception as e:
        print("Lỗi đồng bộ VS Code:", e)

def get_next_port(servers):
    ports = [s.get("port", 2222) for s in servers]
    p = 2222
    while p in ports:
        p += 1
    return p

def is_port_listening(port):
    try:
        res = subprocess.run(["lsof", f"-i:{port}"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return res.returncode == 0
    except Exception:
        return False

def start_tunnel(server):
    bastion_id = get_bastion_id()
    if not bastion_id:
        print("⚠️ Không tìm thấy BASTION_ID để mở tunnel tự động.")
        return

    port = server["port"]
    host = server["host"]
    if is_port_listening(port):
        print(f"✅ Tunnel cho {server['name']} (127.0.0.1:{port}) đã chạy sẵn!")
        return

    params = json.dumps({"host": [host], "portNumber": ["22"], "localPortNumber": [str(port)]})
    cmd = (
        f"aws ssm start-session "
        f"--target {bastion_id} "
        f"--document-name AWS-StartPortForwardingSessionToRemoteHost "
        f"--parameters '{params}' "
        f"--profile prod > /dev/null 2>&1 &"
    )
    os.system(cmd)
    print(f"🚀 Đã bật Tunnel ngầm cho {server['name']} (127.0.0.1:{port})")

def main():
    while True:
        servers = load_servers()
        print("\n==================================================")
        print("💻 QUẢN LÝ & KẾT NỐI SSH SERVER / VS CODE (CRUD)")
        print("==================================================")
        if not servers:
            print("  (Chưa có server nào trong danh sách local)")
        else:
            for i, s in enumerate(servers, 1):
                p_status = "🟢" if is_port_listening(s.get("port", 2222)) else "⚪"
                print(f"  {i}) {p_status} {s['name']} -> IP: {s['host']} | Folder: {s.get('root', '/')} | Port: {s.get('port', 2222)}")
        print("--------------------------------------------------")
        print("  a) ➕ Thêm Server mới (Create)")
        if servers:
            print("  e) ✏️  Sửa Server (Edit)")
            print("  d) 🗑️  Xóa Server (Delete)")
        print("  b) 🔙 Quay lại Menu chính")
        print("==================================================")
        choice = safe_input(f"👉 Chọn (1-{len(servers)} để kết nối, hoặc a/e/d/b): ")

        if choice is None or choice.lower() == "b":
            break
        elif choice.lower() == "a":
            name = safe_input("👉 Nhập tên gợi nhớ: ")
            if name is None:
                print("\n⚠️ Đã hủy thêm server.")
                continue
            if not name:
                print("❌ Tên không được để trống!")
                continue

            host = safe_input("👉 Nhập IP nội bộ: ")
            if host is None:
                print("\n⚠️ Đã hủy thêm server.")
                continue
            if not host:
                print("❌ IP không được để trống!")
                continue

            root_in = safe_input("👉 Thư mục code từ xa [Enter để mặc định /home/ec2-user]: ")
            if root_in is None:
                print("\n⚠️ Đã hủy thêm server.")
                continue
            root = root_in or "/home/ec2-user"

            sw_in = safe_input("👉 User chuyển quyền Terminal [Enter để mặc định git]: ")
            if sw_in is None:
                print("\n⚠️ Đã hủy thêm server.")
                continue
            sw = sw_in or "git"

            usr_in = safe_input("👉 User SSH kết nối [Enter để mặc định ec2-user]: ")
            if usr_in is None:
                print("\n⚠️ Đã hủy thêm server.")
                continue
            usr = usr_in or "ec2-user"

            key_in = safe_input("👉 Đường dẫn Private Key [Enter để bỏ qua nếu dùng key mặc định]: ")
            if key_in is None:
                print("\n⚠️ Đã hủy thêm server.")
                continue
            key = key_in

            port = get_next_port(servers)

            new_server = {
                "name": name,
                "host": host,
                "port": port,
                "user": usr,
                "switch_user": sw,
                "root": root,
                "key": key
            }
            servers.append(new_server)
            save_servers(servers)
            print(f"✅ Đã thêm server [{name}] thành công!")
            print(f"✅ Đã tự động cập nhật ~/.ssh/config & VS Code!")
            start_tunnel(new_server)
        elif choice.lower() == "d" and servers:
            idx = safe_input(f"👉 Nhập số thứ tự Server muốn xóa (1-{len(servers)}): ")
            if idx is None:
                print("\n⚠️ Đã hủy xóa server.")
                continue
            if idx.isdigit() and 1 <= int(idx) <= len(servers):
                deleted = servers.pop(int(idx) - 1)
                save_servers(servers)
                print(f"🗑️ Đã xóa server [{deleted['name']}] khỏi cấu hình!")
            else:
                print("❌ Số thứ tự không hợp lệ!")
        elif choice.lower() == "e" and servers:
            idx = safe_input(f"👉 Nhập số thứ tự Server muốn sửa (1-{len(servers)}): ")
            if idx is None:
                print("\n⚠️ Đã hủy sửa server.")
                continue
            if idx.isdigit() and 1 <= int(idx) <= len(servers):
                s = servers[int(idx) - 1]
                name = safe_input(f"👉 Tên [{s['name']}]: ")
                if name is None: continue
                name = name or s["name"]

                host = safe_input(f"👉 IP nội bộ [{s['host']}]: ")
                if host is None: continue
                host = host or s["host"]

                root = safe_input(f"👉 Thư mục code [{s.get('root', '/')}]: ")
                if root is None: continue
                root = root or s.get("root", "/")

                sw = safe_input(f"👉 User chuyển quyền [{s.get('switch_user', 'git')}]: ")
                if sw is None: continue
                sw = sw or s.get("switch_user", "git")

                key = safe_input(f"👉 File Key [{s.get('key', '')}]: ")
                if key is None: continue
                key = key or s.get("key", "")

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
            s = servers[int(choice) - 1]
            print(f"\n--- THAO TÁC VỚI [{s['name']}] ---")
            print(f"1. 🖥️  Mở Terminal SSH (user {s.get('switch_user', 'git')})")
            print(f"2. 🛢️  Mở đường hầm Tunnel (Port {s['port']} cho VS Code SSH FS)")
            act = safe_input("👉 Chọn [1-2]: ")
            if act is None:
                print("\n⚠️ Đã hủy.")
                continue
            if act == "1":
                start_tunnel(s)
                sw_cmd = f"cd {s.get('root', '/')} && sudo su {s.get('switch_user', 'git')}"
                os.system(f"ssh -t {s['name']} \"{sw_cmd}\"")
            elif act == "2":
                start_tunnel(s)
        else:
            print("❌ Lựa chọn không hợp lệ!")

if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        print("\n\n👋 Đã thoát.")
        sys.exit(0)
    except Exception as e:
        print(f"\n❌ Đã xảy ra lỗi: {e}")
        sys.exit(1)
