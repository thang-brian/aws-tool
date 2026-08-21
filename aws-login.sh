#!/bin/bash

# --- KIỂM TRA CẬP NHẬT TỰ ĐỘNG ---
if [ -f "$HOME/scripts/updater.sh" ]; then
    source "$HOME/scripts/updater.sh"
    check_for_updates
    if [ $? -eq 99 ]; then return 0 2>/dev/null || exit 0; fi
fi
# ---------------------------------

# Dọn dẹp cấu hình credentials cũ
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE

CRED_FILE="$HOME/.aws/credentials"
if [ -f "$CRED_FILE" ]; then
    cp "$CRED_FILE" "${CRED_FILE}.bak"
    sed -i.bak -e '/^[[:space:]]*$/! s/^\([^#]\)/# \1/' "$CRED_FILE"
    rm -f "${CRED_FILE}.bak"
fi

echo "=================================================="
echo "🚀 CHỌN PHƯƠNG THỨC ĐĂNG NHẬP AWS"
echo "=================================================="
echo "1. Đăng nhập qua Web / SSO (Khuyên dùng - No Key)"
echo "2. Đăng nhập qua MFA (Access Key cũ)"
echo "=================================================="
printf "👉 Chọn [1/2]: "
read LOGIN_CHOICE

if [ "$LOGIN_CHOICE" = "1" ]; then
    echo "----------------------------------------"
    echo "🌍 Đang khởi động trình duyệt để đăng nhập SSO..."
    aws login || aws sso login
    
    if [ $? -eq 0 ]; then
        echo "✅ Đăng nhập Web thành công! Đang kiểm tra danh tính..."
        aws sts get-caller-identity
    else
        echo "❌ Đăng nhập thất bại. Vui lòng kiểm tra lại cấu hình AWS SSO."
    fi

elif [ "$LOGIN_CHOICE" = "2" ]; then
    # --- THAO TÁC CŨ: MFA ---
    SOURCE_PROFILE="japandev"
    TARGET_PROFILE="mfa"
    REGION="ap-northeast-1"

    # Mở lại key cũ trong file credentials cho japandev (xoá dấu #)
    if [ -f "$CRED_FILE" ]; then
        sed -i.bak '/# \[japandev\]/,/^$/ s/^# //' "$CRED_FILE"
        rm -f "${CRED_FILE}.bak"
    fi

    echo "🔍 Đang kiểm tra danh tính profile [$SOURCE_PROFILE]..."
    IDENTITY_JSON=$(aws sts get-caller-identity --profile $SOURCE_PROFILE --output json 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo "❌ Lỗi: Không thể đọc profile '$SOURCE_PROFILE' để lấy MFA."
        echo "Vui lòng mở file ~/.aws/credentials kiểm tra lại Access Key."
        return 1 2>/dev/null || exit 1
    fi

    USER_ARN=$(echo $IDENTITY_JSON | python3 -c "import sys, json; print(json.load(sys.stdin)['Arn'])")
    echo "✅ Xin chào: $USER_ARN"

    echo "📡 Đang tìm kiếm thiết bị MFA..."
    MFA_JSON=$(aws iam list-mfa-devices --profile $SOURCE_PROFILE --output json)
    MFA_SERIAL=$(echo $MFA_JSON | python3 -c "import sys, json; devices=json.load(sys.stdin).get('MFADevices', []); print(devices[0]['SerialNumber']) if devices else print('')")

    if [ -z "$MFA_SERIAL" ]; then
        echo "❌ Lỗi: Không tìm thấy thiết bị MFA nào!"
        return 1 2>/dev/null || exit 1
    fi

    echo "🎯 Đã tìm thấy MFA: $MFA_SERIAL"
    printf "👉 Nhập mã MFA (6 số) trên điện thoại: "
    read TOKEN_CODE

    if [ -z "$TOKEN_CODE" ]; then
        echo "❌ Chưa nhập mã code!"
        return 1 2>/dev/null || exit 1
    fi

    echo "⏳ Đang xác thực với AWS..."
    CREDENTIALS_JSON=$(aws sts get-session-token \
        --serial-number $MFA_SERIAL \
        --token-code $TOKEN_CODE \
        --profile $SOURCE_PROFILE \
        --duration-seconds 129600 \
        --output json)

    if [ $? -ne 0 ]; then
        echo "❌ Xác thực thất bại! (Sai mã code)"
        return 1 2>/dev/null || exit 1
    fi

    ACCESS_KEY=$(echo $CREDENTIALS_JSON | python3 -c "import sys, json; print(json.load(sys.stdin)['Credentials']['AccessKeyId'])")
    SECRET_KEY=$(echo $CREDENTIALS_JSON | python3 -c "import sys, json; print(json.load(sys.stdin)['Credentials']['SecretAccessKey'])")
    SESSION_TOKEN=$(echo $CREDENTIALS_JSON | python3 -c "import sys, json; print(json.load(sys.stdin)['Credentials']['SessionToken'])")

    aws configure set profile.$TARGET_PROFILE.aws_access_key_id "$ACCESS_KEY"
    aws configure set profile.$TARGET_PROFILE.aws_secret_access_key "$SECRET_KEY"
    aws configure set profile.$TARGET_PROFILE.aws_session_token "$SESSION_TOKEN"
    aws configure set profile.$TARGET_PROFILE.region "$REGION"

    export AWS_PROFILE=$TARGET_PROFILE
    echo "✅ Đã lưu phiên đăng nhập thành công vào profile [$TARGET_PROFILE]!"
    echo "🚀 Hệ thống đã tự động gán biến môi trường AWS_PROFILE=mfa cho bạn."
    aws sts get-caller-identity
else
    echo "❌ Lựa chọn không hợp lệ."
fi
