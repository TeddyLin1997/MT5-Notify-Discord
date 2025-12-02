/**
 * Discord Webhook 測試腳本
 * 用於驗證 Discord Webhook 是否正常工作
 */

const axios = require('axios');

const DISCORD_WEBHOOK_URL = process.env.DISCORD_WEBHOOK_URL || 'YOUR_WEBHOOK_URL';

async function testDiscordWebhook() {
  console.log('🧪 測試 Discord Webhook...\n');

  const testEmbed = {
    embeds: [
      {
        title: '🎉 MT5-Notify 測試通知',
        description: '如果你看到這則訊息，代表 Discord Webhook 設定成功！',
        color: 3066993, // Green
        fields: [
          { name: '狀態', value: '✅ 正常運行', inline: true },
          { name: '測試時間', value: new Date().toLocaleString('zh-TW'), inline: true },
        ],
        footer: {
          text: 'MT5-Notify System Test',
        },
        timestamp: new Date().toISOString(),
      },
    ],
  };

  try {
    const response = await axios.post(DISCORD_WEBHOOK_URL, testEmbed, {
      headers: { 'Content-Type': 'application/json' },
    });

    console.log('✅ Discord Webhook 測試成功！');
    console.log(`📨 狀態碼: ${response.status}`);
    console.log('💬 請檢查你的 Discord 頻道是否收到測試訊息\n');
  } catch (error) {
    console.error('❌ Discord Webhook 測試失敗！\n');
    if (error.response) {
      console.error(`狀態碼: ${error.response.status}`);
      console.error(`錯誤訊息: ${JSON.stringify(error.response.data, null, 2)}\n`);
    } else {
      console.error(`錯誤: ${error.message}\n`);
    }
    process.exit(1);
  }
}

// 執行測試
if (DISCORD_WEBHOOK_URL === 'YOUR_WEBHOOK_URL') {
  console.error('❌ 請先設定 DISCORD_WEBHOOK_URL 環境變數！\n');
  console.log('使用方式:');
  console.log('  DISCORD_WEBHOOK_URL="your-url" node scripts/test-discord.js\n');
  process.exit(1);
}

testDiscordWebhook();
