import axios, { AxiosError } from 'axios';
import { MT5Event, EventType, DiscordWebhookPayload, DiscordEmbed, DiscordColor } from '../types';
import { config } from '../config';
import { logger } from '../utils/logger';

/**
 * 將 MT5 事件轉換為 Discord Embed
 */
export function buildDiscordEmbed(event: MT5Event): DiscordEmbed {
  const { eventType, symbol, side, volume, price, sl, tp, comment, magic, profit, balance } = event;

  // 根據事件類型決定標題和顏色
  let description: string;
  let color: DiscordColor;

  switch (eventType) {
    case EventType.ORDER_OPEN:
      description = '📈 開倉通知';
      color = DiscordColor.GREEN;
      break;
    case EventType.ORDER_CLOSE:
      description = '📉 平倉通知';
      color = DiscordColor.RED;
      break;
    case EventType.PARTIAL_CLOSE:
      description = '📉 平倉通知';
      color = DiscordColor.RED;
      break;
    case EventType.SL_TP_MODIFY:
      description = '🔧 TP/SL 修改';
      color = DiscordColor.YELLOW;
      break;
    case EventType.ORDER_MODIFY:
      description = '🔧 訂單修改';
      color = DiscordColor.YELLOW;
      break;
    case EventType.PENDING_ORDER_ADD:
      description = '📝 掛單新增';
      color = DiscordColor.BLUE;
      break;
    case EventType.PENDING_ORDER_MODIFY:
      description = '✏️ 掛單修改';
      color = DiscordColor.BLUE;
      break;
    case EventType.PENDING_ORDER_DELETE:
      description = '🗑️ 掛單刪除';
      color = DiscordColor.BLUE;
      break;
    default:
      description = '🔔 交易事件';
      color = DiscordColor.BLUE;
  }

  // 構建描述（策略名稱粗體顯示）
  const strategyName = `${comment} 策略` || '未命名策略';
  const title = `**${strategyName}**`;

  // 根據事件類型構建欄位
  const fields = [
    { name: '交易品種', value: `${symbol}`, inline: true },
    { name: '交易數量', value: volume.toFixed(2), inline: true },
    { name: '交易方向', value: side === 'BUY' ? 'Buy' : 'Sell', inline: true },
  ];

  // 開倉/掛單：顯示入場價格、SL、TP
  if (eventType === EventType.ORDER_OPEN ||
    eventType === EventType.PENDING_ORDER_ADD ||
    eventType === EventType.PENDING_ORDER_MODIFY) {
    fields.push(
      { name: '入場價格', value: price.toFixed(5), inline: true },
      { name: 'TP', value: tp > 0 ? tp.toFixed(5) : '未設置', inline: true },
      { name: 'SL', value: sl > 0 ? sl.toFixed(5) : '未設置', inline: true },
    );
  }

  // 平倉：顯示入場價格和平倉價格
  if (eventType === EventType.ORDER_CLOSE || eventType === EventType.PARTIAL_CLOSE) {
    // 注意：MT5 的 price 在平倉時是平倉價格，這裡需要從 Deal 獲取開倉價格
    fields.push(
      { name: '平倉價格', value: price.toFixed(5), inline: true }
    );

    // 新增損益資訊
    if (profit !== undefined) {
      const profitEmoji = profit >= 0 ? '💰' : '❌';
      const profitSign = profit >= 0 ? '+' : '';
      fields.push({
        name: `${profitEmoji} 損益`,
        value: `${profitSign}${profit.toFixed(2)} USD`,
        inline: true,
      });
    }
  }

  // SL/TP 修改：顯示新的 SL/TP
  if (eventType === EventType.SL_TP_MODIFY || eventType === EventType.ORDER_MODIFY) {
    fields.push(
      { name: 'TP', value: tp > 0 ? tp.toFixed(5) : '未設置', inline: true },
      { name: 'SL', value: sl > 0 ? sl.toFixed(5) : '未設置', inline: true },
    );
  }

  // 構建 Embed
  const embed: DiscordEmbed = {
    title,
    description,
    color,
    fields,
    timestamp: new Date(event.timestamp * 1000).toISOString(),
    footer: {
      text: `Order ID: ${event.orderId}`,
    },
  };

  return embed;
}

/**
 * 發送 Discord Webhook（支援重試機制）
 */
export async function sendDiscordNotification(event: MT5Event): Promise<void> {
  const embed = buildDiscordEmbed(event);
  const payload: DiscordWebhookPayload = { embeds: [embed] };

  let attempt = 0;
  let lastError: Error | null = null;

  while (attempt < config.maxRetryAttempts) {
    try {
      await axios.post(config.discordWebhookUrl!, payload, {
        headers: { 'Content-Type': 'application/json' },
        timeout: 5000,
      });

      logger.info('Discord notification sent successfully', {
        eventType: event.eventType,
        symbol: event.symbol,
        attempt: attempt + 1,
      });
      return;
    } catch (error) {
      attempt++;
      lastError = error as Error;

      const axiosError = error as AxiosError;
      logger.warn('Discord notification failed', {
        attempt,
        status: axiosError.response?.status,
        statusText: axiosError.response?.statusText,
        error: axiosError.message,
      });

      // 如果還有重試次數，等待後重試（指數退避）
      if (attempt < config.maxRetryAttempts) {
        const delay = config.retryDelayMs * Math.pow(2, attempt - 1);
        logger.debug(`Retrying in ${delay}ms...`);
        await new Promise((resolve) => setTimeout(resolve, delay));
      }
    }
  }

  // 所有重試失敗
  logger.error('Discord notification failed after all retries', {
    eventType: event.eventType,
    symbol: event.symbol,
    attempts: config.maxRetryAttempts,
    error: lastError?.message,
  });

  throw new Error(`Failed to send Discord notification after ${config.maxRetryAttempts} attempts`);
}
