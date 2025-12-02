#!/bin/bash

# Zeabur 部署前置設定腳本

set -e

echo "🚀 MT5-Notify Zeabur 部署設定"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 檢查是否在 backend 目錄
if [ ! -f "package.json" ]; then
    echo "❌ 請在 backend 目錄下執行此腳本"
    exit 1
fi

# 生成新的 API Token
echo ""
echo "📋 步驟 1: 生成 API_SECRET_TOKEN"
API_TOKEN=$(openssl rand -hex 32)
echo "✅ 已生成 Token: $API_TOKEN"
echo ""
echo "請將以下 Token 複製到 Zeabur 環境變數:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "API_SECRET_TOKEN=$API_TOKEN"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 建立 .env.zeabur 範本
echo "📋 步驟 2: 建立 .env.zeabur 範本"
cat > .env.zeabur <<EOF
# Zeabur 環境變數（請在 Zeabur Dashboard 設定）
PORT=8080
NODE_ENV=production
API_SECRET_TOKEN=$API_TOKEN
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_TOKEN
RATE_LIMIT_WINDOW_MS=60000
RATE_LIMIT_MAX_REQUESTS=100
MAX_RETRY_ATTEMPTS=3
RETRY_DELAY_MS=1000
EOF
echo "✅ 已建立 .env.zeabur"
echo ""

# 檢查 Git 狀態
echo "📋 步驟 3: 檢查 Git 狀態"
if [ -d "../.git" ]; then
    echo "✅ Git 儲存庫已存在"
else
    echo "⚠️  尚未初始化 Git，請執行:"
    echo "   cd .. && git init"
fi
echo ""

# 顯示下一步指示
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎯 下一步："
echo ""
echo "1. 將專案推送到 GitHub/GitLab:"
echo "   git add ."
echo "   git commit -m 'Ready for Zeabur deployment'"
echo "   git push origin main"
echo ""
echo "2. 前往 Zeabur Dashboard:"
echo "   https://zeabur.com"
echo ""
echo "3. 建立新專案並連接儲存庫"
echo ""
echo "4. 設定環境變數（使用上方生成的 Token）"
echo ""
echo "5. 等待部署完成"
echo ""
echo "完整指南請參考: ZEABUR_DEPLOYMENT.md"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
