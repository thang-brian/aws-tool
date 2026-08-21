#!/bin/bash

# --- KIỂM TRA CẬP NHẬT TỰ ĐỘNG ---
if [ -f "$HOME/scripts/updater.sh" ]; then
    source "$HOME/scripts/updater.sh"
    check_for_updates
fi
# ---------------------------------

# --- CẤU HÌNH ---
# Profile gốc chứa User IAM (User thật)
SOURCE_PROFILE="japandev"
# Profile đích để lưu Session Token
TARGET_PROFILE="mfa"
# Region mặc định
REGION="ap-northeast-1"
# ----------------

# 1. Reset biến môi trường
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE

echo "🔍 Đang kiểm tra danh tính profile [$SOURCE_PROFILE]..."

# 2. Lấy thông tin người dùng (Check Identity)
IDENTITY_JSON=$(aws sts get-caller-identity --profile $SOURCE_PROFILE --output json 2>&1)
if [ $? -ne 0 ]; then
    echo "❌ Lỗi: Không thể đọc profile '$SOURCE_PROFILE'. Kiểm tra lại file ~/.aws/credentials"
    echo "Chi tiết lỗi: $IDENTITY_JSON"
    exit 1
fi

USER_ARN=$(echo $IDENTITY_JSON | python3 -c "import sys, json; print(json.load(sys.stdin)['Arn'])")
echo "✅ Xin chào: $USER_ARN"

# 3. Tự động lấy MFA Serial Number
echo "📡 Đang tìm kiếm thiết bị MFA..."
MFA_JSON=$(aws iam list-mfa-devices --profile $SOURCE_PROFILE --output json)
MFA_SERIAL=$(echo $MFA_JSON | python3 -c "import sys, json; devices=json.load(sys.stdin).get('MFADevices', []); print(devices[0]['SerialNumber']) if devices else print('')")

if [ -z "$MFA_SERIAL" ]; then
    echo "❌ Lỗi: Không tìm thấy thiết bị MFA nào cho user này!"
    exit 1
fi

echo "🎯 Đã tìm thấy MFA Device: $MFA_SERIAL"
echo "----------------------------------------"

# 4. Nhập mã code
read -p "👉 Nhập mã MFA (6 số) trên điện thoại: " TOKEN_CODE

if [ -z "$TOKEN_CODE" ]; then
    echo "❌ Chưa nhập mã code!"
    exit 1
fi

# 5. Gọi AWS lấy Token
echo "⏳ Đang xác thực với AWS..."
CREDENTIALS_JSON=$(aws sts get-session-token \
    --serial-number $MFA_SERIAL \
    --token-code $TOKEN_CODE \
    --profile $SOURCE_PROFILE \
    --duration-seconds 129600 \
    --output json)

if [ $? -ne 0 ]; then
    echo "❌ Xác thực thất bại! (Sai mã code hoặc lỗi mạng)"
    exit 1
fi

# 6. Parse Key
ACCESS_KEY=$(echo $CREDENTIALS_JSON | python3 -c "import sys, json; print(json.load(sys.stdin)['Credentials']['AccessKeyId'])")
SECRET_KEY=$(echo $CREDENTIALS_JSON | python3 -c "import sys, json; print(json.load(sys.stdin)['Credentials']['SecretAccessKey'])")
SESSION_TOKEN=$(echo $CREDENTIALS_JSON | python3 -c "import sys, json; print(json.load(sys.stdin)['Credentials']['SessionToken'])")

# 7. Lưu vào profile [mfa]
aws configure set profile.$TARGET_PROFILE.aws_access_key_id "$ACCESS_KEY"
aws configure set profile.$TARGET_PROFILE.aws_secret_access_key "$SECRET_KEY"
aws configure set profile.$TARGET_PROFILE.aws_session_token "$SESSION_TOKEN"
aws configure set profile.$TARGET_PROFILE.region "$REGION"

echo "✅ Đã cập nhật xong profile [$TARGET_PROFILE]!"
echo "----------------------------------------"
echo "🚀 Chạy lệnh sau để kích hoạt:"
echo ""
echo "export AWS_PROFILE=$TARGET_PROFILE"
echo ""
