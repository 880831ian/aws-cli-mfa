#! /bin/bash

USER_NAME=$1
MFA_CODE=$2

# 顏色設定
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
WHITE="\033[0m"

if [ -z $USER_NAME ] || [ -z $MFA_CODE ]; then
    echo -e "\n${YELLOW}提醒說明：請輸入使用者名稱 與 MFA 驗證碼\n格式如下：./aws_mfa.sh ian_zhuang 235821 << (請依照手機上的 MFA 號碼)。${WHITE}\n"
    exit 1
fi

if [[ ! "$MFA_CODE" =~ ^[0-9]{6}$ ]]; then
    echo -e "\n${YELLOW}提醒說明：MFA 驗證碼只支援 6 碼數字。${WHITE}\n"
    exit 1
fi

MFA_DEVICES_NUMBER=$(aws iam list-mfa-devices --user-name ${USER_NAME} | jq -r '.MFADevices[0].SerialNumber')

if [ -z $MFA_DEVICES_NUMBER ]; then
    echo -e "\n${RED}錯誤說明：MFA 裝置不存在，請確認使用者名稱是否輸入正確${WHITE}\n"
    exit 1
fi

MFA_INFO=$(aws sts get-session-token --duration-seconds 129600 --serial-number ${MFA_DEVICES_NUMBER} --token-code ${MFA_CODE})

if [ $? -eq 0 ]; then
    MFA_ACCESS_KEY_ID=$(echo $MFA_INFO | jq -r '.Credentials.AccessKeyId')
    MFA_SECRET_ACCESS_KEY=$(echo $MFA_INFO | jq -r '.Credentials.SecretAccessKey')
    MFA_SESSION_TOKEN=$(echo $MFA_INFO | jq -r '.Credentials.SessionToken')
    MFA_EXPIRATION=$(echo $MFA_INFO | jq -r '.Credentials.Expiration')

    # 計算 MFA 到期時間(轉換時區)
    MFA_0_TIME=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$(echo "$MFA_EXPIRATION" | sed 's/+00:00//')" "+%Y-%m-%d %H:%M:%S")
    MFA_8_TIME=$(date -j -v+8H -f "%Y-%m-%d %H:%M:%S" "$MFA_0_TIME" "+%Y-%m-%d %H:%M:%S")

    MFA_CREDENTIALS="[mfa]\naws_access_key_id = $MFA_ACCESS_KEY_ID\naws_secret_access_key = $MFA_SECRET_ACCESS_KEY\naws_session_token = $MFA_SESSION_TOKEN"

    # 檢查是否已經有 [mfa] 區塊
    if grep -q "\[mfa\]" ~/.aws/credentials; then
        # 更新 [mfa] 區塊
        sed -i '' '/\[mfa\]/,/^$/d' ~/.aws/credentials
        echo -e "$MFA_CREDENTIALS" >>~/.aws/credentials
    else
        # 新增 [mfa] 區塊
        echo -e "\n\n$MFA_CREDENTIALS" >>~/.aws/credentials
    fi

    echo -e "\n${GREEN}MFA 驗證成功，將 Key 跟 Token 加入or修改到 ~/.aws/credentials 檔案中${WHITE}"
    echo -e "${BLUE}到期時間：${MFA_8_TIME}${WHITE}\n"
else
    echo -e "\n${RED}MFA 驗證失敗，請確認 MFA 驗證碼是否正確${WHITE}\n"
    exit 1
fi
