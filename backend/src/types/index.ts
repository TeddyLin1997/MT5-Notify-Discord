/**
 * MT5 事件類型定義
 */
export enum EventType {
  ORDER_OPEN = 'ORDER_OPEN',
  ORDER_CLOSE = 'ORDER_CLOSE',
  ORDER_MODIFY = 'ORDER_MODIFY',
  PENDING_ORDER_ADD = 'PENDING_ORDER_ADD',
  PENDING_ORDER_MODIFY = 'PENDING_ORDER_MODIFY',
  PENDING_ORDER_DELETE = 'PENDING_ORDER_DELETE',
  SL_TP_MODIFY = 'SL_TP_MODIFY',
  PARTIAL_CLOSE = 'PARTIAL_CLOSE',
}

/**
 * 交易方向
 */
export enum TradeSide {
  BUY = 'BUY',
  SELL = 'SELL',
}

/**
 * MT5 交易事件資料結構
 */
export interface MT5Event {
  eventType: EventType;
  orderId: number;
  dealId?: number;
  symbol: string;
  side: TradeSide;
  volume: number;
  price: number;
  sl: number;
  tp: number;
  comment: string;
  magic: number;
  timestamp: number;
  profit?: number;
  balance?: number;
}

/**
 * Discord Embed 顏色對應
 */
export enum DiscordColor {
  GREEN = 3066993,   // 開倉
  RED = 15158332,    // 平倉
  BLUE = 3447003,    // 掛單
  YELLOW = 16776960, // 修改
}

/**
 * Discord Embed Field
 */
export interface DiscordField {
  name: string;
  value: string;
  inline?: boolean;
}

/**
 * Discord Embed 結構
 */
export interface DiscordEmbed {
  title: string;
  description?: string;
  color: DiscordColor;
  fields: DiscordField[];
  timestamp: string;
  footer?: {
    text: string;
  };
}

/**
 * Discord Webhook Payload
 */
export interface DiscordWebhookPayload {
  embeds: DiscordEmbed[];
}
