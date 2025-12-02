import { Router, Request, Response } from 'express';
import { MT5Event } from '../types';
import { authenticateToken } from '../middleware/auth';
import { validateMT5Event } from '../middleware/validation';
import { sendDiscordNotification } from '../services/discordService';
import { logger } from '../utils/logger';

const router = Router();

/**
 * POST /mt5/event
 * 接收 MT5 EA 發送的交易事件
 */
router.post('/event', authenticateToken, validateMT5Event, async (req: Request, res: Response) => {
  const event = req.body as MT5Event;

  logger.info('Received MT5 event', {
    eventType: event.eventType,
    symbol: event.symbol,
    side: event.side,
    orderId: event.orderId,
  });

  try {
    // 發送 Discord 通知
    await sendDiscordNotification(event);

    res.status(200).json({
      success: true,
      message: 'Event processed and notification sent',
      orderId: event.orderId,
    });
  } catch (error) {
    logger.error('Failed to process MT5 event', {
      error: error instanceof Error ? error.message : 'Unknown error',
      event,
    });

    // 即使 Discord 通知失敗,仍回傳 500 讓 EA 重試
    res.status(500).json({
      success: false,
      error: 'Failed to send notification',
    });
  }
});

/**
 * GET /mt5/health
 * 健康檢查端點
 */
router.get('/health', (req: Request, res: Response) => {
  res.status(200).json({
    status: 'ok',
    timestamp: new Date().toISOString(),
  });
});

export default router;
