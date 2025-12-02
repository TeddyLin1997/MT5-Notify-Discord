# MT5-Notify Backend

MT5 交易事件監控後端 API - 接收 EA 發送的交易事件並推送至 Discord。

## 🚀 快速開始

### 1. 安裝依賴
```bash
npm install
```

### 2. 設定環境變數
```bash
cp .env.example .env
# 編輯 .env 填入以下必要參數：
# - API_SECRET_TOKEN
# - DISCORD_WEBHOOK_URL
```

### 3. 開發模式運行
```bash
npm run dev
```

### 4. 構建生產版本
```bash
npm run build
npm start
```

## 📁 專案結構

```
backend/
├── src/
│   ├── config/           # 環境配置
│   ├── middleware/       # 中間件（認證、驗證）
│   ├── routes/           # API 路由
│   ├── services/         # 業務邏輯（Discord）
│   ├── types/            # TypeScript 類型定義
│   ├── utils/            # 工具函數（Logger）
│   └── index.ts          # 應用入口
├── logs/                 # 日誌檔案
├── .env.example          # 環境變數範例
├── package.json
└── tsconfig.json
```

## 🔌 API 端點

### 健康檢查
```bash
GET /api/mt5/health
```

**回應範例：**
```json
{
  "status": "ok",
  "timestamp": "2025-12-02T10:30:00.000Z"
}
```

### 接收 MT5 事件
```bash
POST /api/mt5/event
Authorization: Bearer YOUR_TOKEN
Content-Type: application/json
```

**請求範例：**
```json
{
  "eventType": "ORDER_OPEN",
  "orderId": 123456,
  "dealId": 98765,
  "symbol": "BTCUSD",
  "side": "BUY",
  "volume": 0.1,
  "price": 68321.5,
  "sl": 68000,
  "tp": 69000,
  "comment": "Grid#1",
  "magic": 1001,
  "timestamp": 1738501000
}
```

**回應範例：**
```json
{
  "success": true,
  "message": "Event processed and notification sent",
  "orderId": 123456
}
```

## 🎨 Discord 訊息格式

系統會根據事件類型自動生成不同顏色的 Embed：

- **開倉** 📈：綠色（#2ECC71）
- **平倉** 📉：紅色（#E74C3C）
- **掛單** 📝：藍色（#3498DB）
- **修改** 🔧：黃色（#F1C40F）

## 🔒 安全機制

### 1. Bearer Token 認證
所有 API 請求需攜帶 Authorization Header：
```
Authorization: Bearer your-super-secret-token-12345
```

### 2. Rate Limiting
- 預設：60 秒內最多 100 次請求
- 超過限制回應 429 Too Many Requests

### 3. 請求驗證
- 檢查必填欄位
- 驗證資料類型
- 防止無效事件類型

### 4. 錯誤處理與重試
- Discord API 失敗自動重試（最多 3 次）
- 指數退避策略（1s → 2s → 4s）
- 完整錯誤日誌記錄

## 📊 日誌系統

日誌檔案位於 `logs/` 目錄：

- **combined.log**: 所有日誌
- **error.log**: 僅錯誤日誌

日誌等級：
- `debug`: 開發階段詳細資訊
- `info`: 一般資訊（生產環境預設）
- `warn`: 警告訊息
- `error`: 錯誤訊息

## 🧪 測試

### 手動測試事件發送
```bash
curl -X POST http://localhost:3000/api/mt5/event \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-token" \
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
  }'
```

## 🌍 環境變數

| 變數 | 必要 | 預設值 | 說明 |
|------|------|--------|------|
| `PORT` | ❌ | `3000` | 伺服器埠號 |
| `NODE_ENV` | ❌ | `development` | 運行環境 |
| `API_SECRET_TOKEN` | ✅ | - | API 認證 Token |
| `DISCORD_WEBHOOK_URL` | ✅ | - | Discord Webhook URL |
| `RATE_LIMIT_WINDOW_MS` | ❌ | `60000` | 限流時間窗口（毫秒） |
| `RATE_LIMIT_MAX_REQUESTS` | ❌ | `100` | 最大請求次數 |
| `MAX_RETRY_ATTEMPTS` | ❌ | `3` | Discord API 重試次數 |
| `RETRY_DELAY_MS` | ❌ | `1000` | 重試延遲（毫秒） |

## 🚢 部署

詳細部署步驟請參考 [DEPLOYMENT.md](../DEPLOYMENT.md)

### Heroku 快速部署
```bash
heroku create your-app-name
heroku config:set API_SECRET_TOKEN="your-token"
heroku config:set DISCORD_WEBHOOK_URL="your-webhook-url"
git push heroku main
```

## 📝 License

MIT License - 自由使用與修改
