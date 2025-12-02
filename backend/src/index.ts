import express, { Request, Response, NextFunction } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import path from 'path';
import { config } from './config';
import { logger } from './utils/logger';
import mt5Routes from './routes/mt5';

const app = express();

// ========== 安全與中間件設置 ==========

// Helmet - 安全標頭
app.use(helmet());

// CORS - 允許跨域請求
app.use(
  cors({
    origin: config.nodeEnv === 'production' ? false : '*', // 生產環境建議限制來源
    credentials: true,
  })
);

// Body Parser
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Rate Limiting - 防止 DDoS 攻擊
const limiter = rateLimit({
  windowMs: config.rateLimitWindowMs,
  max: config.rateLimitMaxRequests,
  message: 'Too many requests from this IP, please try again later',
  standardHeaders: true,
  legacyHeaders: false,
});

app.use('/api', limiter);

app.get('/favicon.ico', (req: Request, res: Response) => {
  res.sendFile(path.resolve(__dirname, '../favicon.ico'));
});

// ========== 路由設置 ==========

// 根路徑
app.get('/', (req: Request, res: Response) => {
  res.json({
    name: 'MT5 Notify API',
    version: '1.0.0',
    status: 'running',
    endpoints: {
      health: '/api/mt5/health',
      event: 'POST /api/mt5/event',
    },
  });
});

// MT5 路由
app.use('/api/mt5', mt5Routes);

// ========== 錯誤處理 ==========

// 404 處理
app.use((req: Request, res: Response) => {
  logger.warn('Route not found', { path: req.path, method: req.method });
  res.status(404).json({ error: 'Route not found' });
});

// 全局錯誤處理
app.use((err: Error, req: Request, res: Response, next: NextFunction) => {
  logger.error('Unhandled error', {
    error: err.message,
    stack: err.stack,
    path: req.path,
  });

  res.status(500).json({
    error: 'Internal server error',
    message: config.nodeEnv === 'development' ? err.message : undefined,
  });
});

// ========== 啟動伺服器 ==========

app.listen(config.port, () => {
  logger.info(`MT5 Notify API started`, {
    port: config.port,
    nodeEnv: config.nodeEnv,
    timestamp: new Date().toISOString(),
  });

  if (config.nodeEnv === 'development') {
    logger.info('API Endpoints:', {
      base: `http://localhost:${config.port}`,
      health: `http://localhost:${config.port}/api/mt5/health`,
      event: `POST http://localhost:${config.port}/api/mt5/event`,
    });
  }
});

// 優雅關閉
process.on('SIGINT', () => {
  logger.info('SIGINT received, shutting down gracefully...');
  process.exit(0);
});

process.on('SIGTERM', () => {
  logger.info('SIGTERM received, shutting down gracefully...');
  process.exit(0);
});
