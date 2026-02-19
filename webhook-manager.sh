#!/bin/bash

# =================================================================
# Webhook 容器化管理器 (纯 Shell 增强版 - curl 邮件版)
# 功能：自动安装、配置管理、支持 SSL 邮件通知 (curl SMTP)
# =================================================================

# 路径定义
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF_DATA_DIR="$BASE_DIR/hooks_configs"
SYS_WORKDIR="/etc/webhook"
SYS_HOOKS_JSON="$SYS_WORKDIR/hooks.json"
MAIL_CONF="$BASE_DIR/mail.conf"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 初始化目录
mkdir -p "$CONF_DATA_DIR"
mkdir -p "$SYS_WORKDIR"

# 权限检查
[[ "$(id -u)" != "0" ]] && echo -e "${RED}错误: 请使用 root 权限运行${NC}" && exit 1

# 1. 环境检查与安装
check_env() {
    # 检查 Webhook 核心
    if ! command -v webhook &> /dev/null; then
        echo -e "${YELLOW}正在安装 Webhook 环境...${NC}"
        wget -qO webhook.tar.gz https://github.com/adnanh/webhook/releases/download/2.8.1/webhook-linux-amd64.tar.gz
        tar -xzf webhook.tar.gz && mv webhook-linux-amd64/webhook /usr/local/bin/
        rm -rf webhook-linux-amd64 webhook.tar.gz
    fi

    # 检查 curl
    if ! command -v curl &> /dev/null; then
        echo -e "${YELLOW}正在安装 curl...${NC}"
        if command -v apt &> /dev/null; then
            apt update && apt install -y curl
        elif command -v yum &> /dev/null; then
            yum install -y curl
        fi
    fi
}

# 2. 验证邮件配置文件
verify_mail_conf() {
    if [[ ! -f "$MAIL_CONF" ]]; then
        echo -e "${RED}警告: 未发现 $MAIL_CONF，邮件通知功能将不可用。${NC}"
        return 1
    fi

    source "$MAIL_CONF"

    local ok=true
    [[ -z "$SMTP_SERVER" ]] && echo -e "${RED}  缺少 SMTP_SERVER${NC}" && ok=false
    [[ -z "$SMTP_PORT" ]]   && echo -e "${RED}  缺少 SMTP_PORT${NC}"   && ok=false
    [[ -z "$SMTP_USER" ]]   && echo -e "${RED}  缺少 SMTP_USER${NC}"   && ok=false
    [[ -z "$SMTP_PASS" ]]   && echo -e "${RED}  缺少 SMTP_PASS${NC}"   && ok=false
    [[ -z "$MAIL_TO" ]]     && echo -e "${RED}  缺少 MAIL_TO${NC}"     && ok=false

    if [[ "$ok" == true ]]; then
        echo -e "${GREEN}✓ 邮件配置验证通过 (${SMTP_USER} -> ${MAIL_TO} via ${SMTP_SERVER}:${SMTP_PORT})${NC}"
    else
        echo -e "${RED}✗ 邮件配置不完整${NC}"
        return 1
    fi
}

# 3. 发送测试邮件
send_test_mail() {
    if [[ ! -f "$MAIL_CONF" ]]; then
        echo -e "${RED}未找到 $MAIL_CONF${NC}"
        return 1
    fi
    source "$MAIL_CONF"

    local SUBJECT_B64
    SUBJECT_B64=$(echo -n "Webhook邮件测试" | base64)

    echo -e "${YELLOW}正在发送测试邮件到 $MAIL_TO ...${NC}"
    curl --silent --show-error --ssl-reqd \
        --url "smtps://$SMTP_SERVER:465" \
        --user "$SMTP_USER:$SMTP_PASS" \
        --mail-from "$SMTP_USER" \
        --mail-rcpt "$MAIL_TO" \
        -T - <<EOF
From: $SMTP_USER
To: $MAIL_TO
Subject: =?UTF-8?B?${SUBJECT_B64}?=
Date: $(date -R)
Content-Type: text/plain; charset=UTF-8

Webhook 邮件测试
时间: $(date)
服务器: $(hostname)
状态: 配置正常
EOF

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✓ 测试邮件发送成功，请检查收件箱${NC}"
    else
        echo -e "${RED}✗ 测试邮件发送失败${NC}"
    fi
}

# 4. 重建系统配置 hooks.json
rebuild_system_json() {
    echo "[" > "$SYS_HOOKS_JSON"
    local first=true
    for f in "$CONF_DATA_DIR"/*.conf; do
        [[ ! -e "$f" ]] && continue
        source "$f"
        if [[ -f "$SYS_WORKDIR/${HOOK_ID}_deploy.sh" ]]; then
            if [[ "$first" = false ]]; then echo "," >> "$SYS_HOOKS_JSON"; fi
            cat <<EOF >> "$SYS_HOOKS_JSON"
  {
    "id": "$HOOK_ID",
    "execute-command": "$SYS_WORKDIR/${HOOK_ID}_deploy.sh",
    "command-working-directory": "$PROJECT_PATH",
    "trigger-rule": {
      "match": {
        "type": "payload-hash-sha1",
        "secret": "$AUTO_SECRET",
        "parameter": { "source": "header", "name": "X-Hub-Signature" }
      }
    }
  }
EOF
            first=false
        fi
    done
    echo "]" >> "$SYS_HOOKS_JSON"
    systemctl restart webhook 2>/dev/null || echo "Webhook 服务尚未启动"
}

# 5. 安装 Hook (生成执行脚本 - curl 邮件版)
install_hook() {
    local conf_f=$1
    source "$conf_f"
    echo -e "${YELLOW}正在激活项目: $HOOK_ID ...${NC}"

    # 读取邮件配置，生成时直接嵌入
    local _SMTP_SERVER="" _SMTP_USER="" _SMTP_PASS="" _MAIL_TO=""
    if [[ -f "$MAIL_CONF" ]]; then
        source "$MAIL_CONF"
        _SMTP_SERVER="$SMTP_SERVER"
        _SMTP_USER="$SMTP_USER"
        _SMTP_PASS="$SMTP_PASS"
        _MAIL_TO="$MAIL_TO"
    fi

    cat <<OUTER > "$SYS_WORKDIR/${HOOK_ID}_deploy.sh"
#!/bin/bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export HOME="/root"

HOOK_ID="$HOOK_ID"
PROJECT_PATH="$PROJECT_PATH"
DEPLOY_CMD="$DEPLOY_CMD"
SMTP_SERVER="$_SMTP_SERVER"
SMTP_USER="$_SMTP_USER"
SMTP_PASS="$_SMTP_PASS"
MAIL_TO="$_MAIL_TO"

LOG_FILE="/tmp/webhook_\${HOOK_ID}_\$(date +%s).log"

{
    echo "=========================================="
    echo "--- 部署任务开始: \$(date) ---"
    echo "项目ID: \$HOOK_ID"
    echo "运行目录: \$PROJECT_PATH"
    echo "=========================================="

    cd "\$PROJECT_PATH" || { echo "[ERROR] 切换目录失败"; exit 1; }

    echo "[INFO] 执行: \$DEPLOY_CMD"
    eval "\$DEPLOY_CMD"

} > "\$LOG_FILE" 2>&1

EXIT_CODE=\$?
echo "[INFO] Deploy exit code: \$EXIT_CODE" >> "\$LOG_FILE"

# --- 使用 curl 发送邮件通知 ---
if [[ -n "\$SMTP_SERVER" && -n "\$MAIL_TO" ]]; then
    if [ \$EXIT_CODE -eq 0 ]; then
        RAW_SUBJECT="Webhook成功: \$HOOK_ID"
    else
        RAW_SUBJECT="Webhook失败: \$HOOK_ID"
    fi
    SUBJECT_B64=\$(echo -n "\$RAW_SUBJECT" | base64 | tr -d '\n')
    MAIL_BODY=\$(cat "\$LOG_FILE")

    curl --silent --show-error --ssl-reqd \\
        --url "smtps://\${SMTP_SERVER}:465" \\
        --user "\${SMTP_USER}:\${SMTP_PASS}" \\
        --mail-from "\$SMTP_USER" \\
        --mail-rcpt "\$MAIL_TO" \\
        -T - <<MAILEOF
From: \${SMTP_USER}
To: \${MAIL_TO}
Subject: =?UTF-8?B?\${SUBJECT_B64}?=
Date: \$(date -R)
Content-Type: text/plain; charset=UTF-8

\${MAIL_BODY}
MAILEOF

    if [ \$? -eq 0 ]; then
        echo "[MAIL] 邮件发送成功 -> \$MAIL_TO" >> "\$LOG_FILE"
    else
        echo "[MAIL] 邮件发送失败" >> "\$LOG_FILE"
    fi
else
    echo "[WARN] 邮件配置缺失，跳过通知" >> "\$LOG_FILE"
fi

# 清理7天前日志
find /tmp -name "webhook_\${HOOK_ID}_*.log" -mtime +7 -delete
OUTER

    chmod +x "$SYS_WORKDIR/${HOOK_ID}_deploy.sh"
    rebuild_system_json
    echo -e "${GREEN}✓ $HOOK_ID 安装完成。${NC}"
}

# 6. 卸载 Hook
uninstall_hook() {
    local hid=$1
    echo -e "${YELLOW}正在卸载 $hid ...${NC}"
    rm -f "$SYS_WORKDIR/${hid}_deploy.sh"
    rebuild_system_json
    echo -e "${GREEN}✓ $hid 已从系统移除。${NC}"
}

# 7. 设置系统服务
setup_service() {
    cat <<EOF > /etc/systemd/system/webhook.service
[Unit]
Description=Webhook Service
After=network.target

[Service]
ExecStart=/usr/local/bin/webhook -hooks $SYS_HOOKS_JSON -verbose -hotreload
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable webhook > /dev/null 2>&1
    systemctl start webhook
}

# --- 主逻辑 ---
check_env
verify_mail_conf
setup_service

while true; do
    echo -e "\n${YELLOW}==== Webhook 管理系统 (curl 邮件版) ====${NC}"
    echo "1) 安装/恢复 本地配置 (hooks_configs/)"
    echo "2) 卸载/停用 系统 Hook"
    echo "3) 新建 Hook 项目"
    echo "4) 验证邮件配置"
    echo "5) 发送测试邮件"
    echo "6) 退出"
    read -p "选择操作 [1-6]: " choice

    case $choice in
        1)
            found=false
            for f in "$CONF_DATA_DIR"/*.conf; do
                [[ ! -e "$f" ]] && continue
                source "$f"
                if [[ ! -f "$SYS_WORKDIR/${HOOK_ID}_deploy.sh" ]]; then
                    echo -e "${YELLOW}[未安装]${NC} ID: $HOOK_ID"
                    read -p "是否安装? (y/n): " confirm
                    [[ "$confirm" == "y" ]] && install_hook "$f"
                    found=true
                fi
            done
            [[ "$found" == false ]] && echo "无待处理项。"
            ;;
        2)
            found=false
            for f in "$CONF_DATA_DIR"/*.conf; do
                [[ ! -e "$f" ]] && continue
                source "$f"
                if [[ -f "$SYS_WORKDIR/${HOOK_ID}_deploy.sh" ]]; then
                    echo -e "${GREEN}[运行中]${NC} ID: $HOOK_ID"
                    read -p "是否卸载? (y/n): " confirm
                    [[ "$confirm" == "y" ]] && uninstall_hook "$HOOK_ID"
                    found=true
                fi
            done
            [[ "$found" == false ]] && echo "无运行中的项。"
            ;;
        3)
            read -p "项目ID (如 my-app): " N_ID
            read -p "项目路径 (绝对路径): " N_PATH
            read -p "部署命令 (如 git pull && pm2 restart all): " N_CMD
            N_SECRET=$(openssl rand -hex 16)
            C_FILE="$CONF_DATA_DIR/${N_ID}.conf"
            echo -e "HOOK_ID=\"$N_ID\"\nPROJECT_PATH=\"$N_PATH\"\nDEPLOY_CMD=\"$N_CMD\"\nAUTO_SECRET=\"$N_SECRET\"" > "$C_FILE"
            install_hook "$C_FILE"
            echo -e "${GREEN}创建成功！Secret: $N_SECRET${NC}"
            ;;
        4) verify_mail_conf ;;
        5) send_test_mail ;;
        6) exit 0 ;;
    esac
done
