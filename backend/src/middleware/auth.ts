import { Request, Response, NextFunction } from 'express';
import { config } from '../config';
import { logger } from '../utils/logger';

/**
 * 驗證 Bearer Token 中間件
 */
export function authenticateToken(req: Request, res: Response, next: NextFunction) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1]; // Bearer TOKEN

  if (!token) {
    logger.warn('Missing authorization token', { ip: req.ip, path: req.path });
    return res.status(401).json({ error: 'Authorization token required' });
  }

  if (token !== config.apiSecretToken) {
    logger.warn('Invalid authorization token', { ip: req.ip, path: req.path });
    return res.status(401).json({ error: 'Invalid token' });
  }

  logger.debug('Token authenticated successfully', { ip: req.ip });
  next();
}
