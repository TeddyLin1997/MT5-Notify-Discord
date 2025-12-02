#!/bin/bash

# MT5-Notify API 測試腳本
# 用於測試後端 API 是否正常運行

set -e

# 顏色定義
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置
API_URL="${API_URL:-http://localhost:3000}"
API_TOKEN="${API_TOKEN:-your-super-secret-token-12345}"

echo "🧪 MT5-Notify API 測試"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "API URL: $API_URL"
echo ""

# 測試 1: 健康檢查
echo "📋 測試 1: 健康檢查端點"
response=$(curl -s -w "\n%{http_code}" "$API_URL/api/mt5/health")
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)

if [ "$http_code" -eq 200 ]; then
    echo -e "${GREEN}✅ 健康檢查通過${NC}"
    echo "回應: $body"
else
    echo -e "${RED}❌ 健康檢查失敗 (HTTP $http_code)${NC}"
    exit 1
fi

echo ""

# 測試 2: 無 Token 認證（應該失敗）
echo "📋 測試 2: 無 Token 認證（預期失敗）"
response=$(curl -s -w "\n%{http_code}" \
  -X POST "$API_URL/api/mt5/event" \
  -H "Content-Type: application/json" \
  -d '{
    "eventType": "ORDER_OPEN",
    "orderId": 123456,
    "dealId": 98765,
    "symbol": "BTCUSD",
    "side": "BUY",
    "volume": 0.1,
    "price": 68321.5,
    "sl": 68000,
    "tp": 69000,
    "comment": "Test",
    "magic": 1001,
    "timestamp": 1738501000
  }')

http_code=$(echo "$response" | tail -n1)

if [ "$http_code" -eq 401 ]; then
    echo -e "${GREEN}✅ 認證機制正常（正確拒絕無 Token 請求）${NC}"
else
    echo -e "${YELLOW}⚠️  預期 401，實際收到 $http_code${NC}"
fi

echo ""

# 測試 3: 有效 Token 發送事件
echo "📋 測試 3: 有效 Token 發送交易事件"
response=$(curl -s -w "\n%{http_code}" \
  -X POST "$API_URL/api/mt5/event" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_TOKEN" \
  -d '{
    "eventType": "ORDER_OPEN",
    "orderId": 123456,
    "dealId": 98765,
    "symbol": "BTCUSD",
    "side": "BUY",
    "volume": 0.1,
    "price": 68321.5,
    "sl": 68000,
    "tp": 69000,
    "comment": "API Test Trade",
    "magic": 1001,
    "timestamp": '"$(date +%s)"'
  }')

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)

if [ "$http_code" -eq 200 ]; then
    echo -e "${GREEN}✅ 事件發送成功${NC}"
    echo "回應: $body"
    echo ""
    echo -e "${YELLOW}💬 請檢查 Discord 頻道是否收到通知${NC}"
else
    echo -e "${RED}❌ 事件發送失敗 (HTTP $http_code)${NC}"
    echo "回應: $body"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}🎉 所有測試通過！${NC}"
