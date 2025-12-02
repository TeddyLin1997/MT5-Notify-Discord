import { Request, Response, NextFunction } from 'express';
import { MT5Event, EventType, TradeSide } from '../types';
import { logger } from '../utils/logger';

/**
 * 驗證 MT5 事件資料格式
 */
export function validateMT5Event(req: Request, res: Response, next: NextFunction) {
  const event = req.body as Partial<MT5Event>;

  // 必填欄位檢查
  const requiredFields: Array<keyof MT5Event> = [
    'eventType',
    'orderId',
    'symbol',
    'side',
    'volume',
    'price',
    'timestamp',
  ];

  const missingFields = requiredFields.filter((field) => event[field] === undefined || event[field] === null);

  if (missingFields.length > 0) {
    logger.warn('Missing required fields', { missingFields, event });
    return res.status(400).json({
      error: 'Missing required fields',
      fields: missingFields,
    });
  }

  // 檢查空值 (針對 symbol 和 side)
  if (event.symbol === '') {
    return res.status(400).json({ error: 'Symbol cannot be empty' });
  }

  if ((event.side as string) === '') {
    return res.status(400).json({ error: 'Side cannot be empty' });
  }

  // 驗證 eventType
  if (!Object.values(EventType).includes(event.eventType as EventType)) {
    logger.warn('Invalid eventType', { eventType: event.eventType });
    return res.status(400).json({
      error: 'Invalid eventType',
      validTypes: Object.values(EventType),
    });
  }

  // 驗證 side
  if (!Object.values(TradeSide).includes(event.side as TradeSide)) {
    logger.warn('Invalid side', { side: event.side });
    return res.status(400).json({
      error: 'Invalid side',
      validSides: Object.values(TradeSide),
    });
  }

  // 數值驗證
  if (event.volume! <= 0) {
    return res.status(400).json({ error: 'Volume must be greater than 0' });
  }

  if (event.price! <= 0) {
    return res.status(400).json({ error: 'Price must be greater than 0' });
  }

  logger.debug('MT5 event validated successfully', { eventType: event.eventType });
  next();
}
