# webhook-manager — My-Search

简洁的 Shell 脚本仓库，用于管理本地 `webhook`（ad-hoc HTTP webhook）配置、自动生成部署脚本并支持邮件通知（通过 `curl` 发 SMTP）。提供交互式安装/卸载/新建 Hook 功能，并自动注册为 systemd 服务运行。

仓库地址：
[https://github.com/My-Search/webhook-manager.git](https://github.com/My-Search/webhook-manager.git)

---

# 功能特性

* Shell 编写的 webhook 管理工具
* 自动安装 webhook 二进制
* 自动生成部署脚本
* 自动生成 `/etc/webhook/hooks.json`
* 自动创建 systemd 服务
* 支持 hot reload
* 支持部署完成邮件通知

---

# 目录结构

```
webhook-manager/
├── webhook-manager.sh
├── mail.conf
└── hooks_configs/
```

---

# 快速开始

```bash
git clone https://github.com/My-Search/webhook-manager.git
cd webhook-manager
chmod +x webhook-manager.sh
sudo ./webhook-manager.sh
```

---

# 邮件配置（可选）

编辑 `mail.conf`：

```bash
SMTP_SERVER="smtp.gmail.com"
SMTP_PORT="465"
SMTP_USER="your@gmail.com"
SMTP_PASS="your-app-password"
MAIL_TO="target@qq.com"
```

---

# Hook 配置说明

路径：

```
hooks_configs/*.conf
```

示例：

```ini
HOOK_ID="ai-rss-hub"
PROJECT_PATH="/opt/ai-rss-hub"
DEPLOY_CMD="git pull && mvn clean package -DskipTests"
AUTO_SECRET="17cb8c8bbb78fb65894bb8c302beb5fa"
```

字段说明：

| 字段           | 说明           |
| ------------ | ------------ |
| HOOK_ID      | webhook 唯一标识 |
| PROJECT_PATH | 项目路径         |
| DEPLOY_CMD   | 执行命令         |
| AUTO_SECRET  | 签名密钥         |

---

# systemd 管理

```bash
sudo systemctl status webhook
sudo systemctl restart webhook
sudo systemctl stop webhook
```

---

# 🔎 运行日志查看

## 1️⃣ 查看 webhook 服务日志

```bash
sudo journalctl -u webhook -f
```

查看最近 200 行：

```bash
sudo journalctl -u webhook -n 200 --no-pager
```

---

## 2️⃣ 查看部署执行日志

部署后会生成日志：

```
/tmp/webhook_<HOOK_ID>_时间戳.log
```

例如：

```bash
ls -lh /tmp | grep webhook
```

查看：

```bash
tail -f /tmp/webhook_ai-rss-hub_*.log
```

---

## 3️⃣ 查看端口监听

```bash
ss -lntp | grep 9000
```

---

# 🚀 手动触发 Webhook（本地测试）

如果你想在本机手动触发某个 Hook（不依赖 GitHub），可以使用 curl。

假设：

* HOOK_ID = ai-rss-hub
* 监听地址 = [http://localhost:9000](http://localhost:9000)
* AUTO_SECRET = 17cb8c8bbb78fb65894bb8c302beb5fa
* Payload = {}

---

## 方式一：标准触发命令

```bash
curl -X POST http://localhost:9000/hooks/ai-rss-hub \
  -H "Content-Type: application/json" \
  -H "X-Hub-Signature: sha1=$(echo -n '{}' | openssl dgst -sha1 -hmac '17cb8c8bbb78fb65894bb8c302beb5fa' | awk '{print $2}')" \
  -d '{}'
```

---

## 参数说明

| 参数                | 说明                |
| ----------------- | ----------------- |
| /hooks/ai-rss-hub | 必须与 HOOK_ID 一致    |
| X-Hub-Signature   | HMAC-SHA1 签名      |
| AUTO_SECRET       | hooks.conf 中配置的密钥 |
| -d '{}'           | 发送的 JSON 数据       |

---

## 方式二：写成变量版本（推荐）

```bash
SECRET="17cb8c8bbb78fb65894bb8c302beb5fa"
PAYLOAD='{}'
HOOK="ai-rss-hub"

SIGN=$(echo -n "$PAYLOAD" | openssl dgst -sha1 -hmac "$SECRET" | awk '{print $2}')

curl -X POST http://localhost:9000/hooks/$HOOK \
  -H "Content-Type: application/json" \
  -H "X-Hub-Signature: sha1=$SIGN" \
  -d "$PAYLOAD"
```

---

# 触发成功后会发生什么？

1. webhook 收到请求
2. 校验签名
3. 执行 `/etc/webhook/${HOOK_ID}_deploy.sh`
4. 生成日志文件
5. （可选）发送邮件通知

---

# 常见错误

## ❌ 403 Forbidden

原因：

* SECRET 不一致
* Payload 与签名不匹配

解决：

* 确保签名计算使用完全相同的 JSON
* 不要多空格或换行

---

## ❌ 404 Not Found

原因：

* HOOK_ID 不存在
* hooks.json 未更新

解决：

```bash
sudo systemctl restart webhook
```

---

# 安全建议

* 不要公开 AUTO_SECRET
* 不要允许公网随意访问 webhook
* 建议配合 Nginx + IP 白名单

---

# 卸载

```bash
sudo systemctl stop webhook
sudo systemctl disable webhook
sudo rm -rf /etc/webhook
sudo rm -f /usr/local/bin/webhook
sudo rm -f /etc/systemd/system/webhook.service
sudo systemctl daemon-reload
```
