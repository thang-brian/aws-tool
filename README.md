# AWS Tools (Monolithic)

Bộ công cụ tự động hoá mọi thao tác đăng nhập AWS và kết nối Database qua SSM (Không cần SSH/Key). Đã được tối ưu thành **1 file duy nhất**.

## 1. Cài đặt ban đầu
Vì lý do bảo mật, Tool này không chứa các thông tin nhạy cảm (Endpoint DB, Bastion ID).
Bạn cần xin file `secret.txt` từ Leader hoặc tải về máy, sau đó chạy lệnh cài đặt kèm theo đường dẫn file đó:
```bash
# Thay /đường/dẫn/tới/secret.txt bằng đường dẫn thực tế trên máy bạn
bash <(curl -sL "https://raw.githubusercontent.com/thang-brian/aws-tool/refs/heads/master/install.sh") /đường/dẫn/tới/secret.txt
# Lệnh cài đặt sẽ tự động lưu bí mật vào ~/.aws/aws-tools.env và hướng dẫn bạn nạp lại shell.
aws-tools
```
Lần đầu chạy, tool sẽ yêu cầu bạn nhập `Username` để tự động khởi tạo cấu hình `~/.aws/config`.

## 2. Cách sử dụng (Hằng ngày)
Gõ lệnh `aws-tools` (hoặc lệnh cũ `aws-login` đều được) để mở Bảng Menu trung tâm:
```bash
aws-tools
```
Tại Menu, bạn chọn **1** để xác thực Web, sau đó chọn từ **4-7** để mở đường hầm tới Database mong muốn.

## 3. Tích hợp thẳng vào DBeaver (Kết nối 1-Click)
Đây là tính năng tiện lợi nhất. Bạn **không cần mở Terminal**, chỉ cần cấu hình thẳng vào DBeaver.
1. Mở Edit Connection của Database trong DBeaver.
2. Tại mục **Server Host**, điền: `localhost`
3. Tại mục **Port**, điền Port tương ứng: `illust` (5432), `photo` (3306), `common` (3307), `common_test` (3308).
4. Tại mục **Shell Commands** -> **Before connection**, dán đoạn lệnh sau:
   ```bash
   /bin/zsh -c "~/scripts/aws-tools.sh dbeaver <tên_db>"
   # Ví dụ: /bin/zsh -c "~/scripts/aws-tools.sh dbeaver photo"
   ```
5. Đảm bảo tab **SSH Tunnel** trong DBeaver đã bị tắt.

Mỗi khi click Connect, tool sẽ tự mở đường hầm ngầm và copy mật khẩu Token vào Clipboard. Bạn chỉ cần nhấn `Cmd + V` để dán vào ô Password.

## 4. Dùng với DataGrip / Terminal
Nếu bạn dùng tool khác không có tính năng Before Connection, bạn có thể gọi các lệnh tắt từ Terminal:
- `aws-tools tunnel photo` (Mở hầm cho db photo)
- `aws-tools dbeaver common` (Mở hầm & Copy Token DB common)
- `aws-tools ssh /path/to/key.pem` (Kết nối SSH cũ qua Bastion - Nếu cần)
