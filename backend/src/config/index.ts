import dotenv from 'dotenv';

dotenv.config();

export const config = {
  // Server (Zeabur 預設使用 8080，本地開發使用 3000)
  port: parseInt(process.env.PORT || '3000', 10),
  nodeEnv: process.env.NODE_ENV || 'development',

  // Authentication
  apiSecretToken: process.env.API_SECRET_TOKEN,

  // Discord
  discordWebhookUrl: process.env.DISCORD_WEBHOOK_URL,

  // Rate Limiting
  rateLimitWindowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS || '60000', 10),
  rateLimitMaxRequests: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS || '100', 10),

  // Retry Configuration
  maxRetryAttempts: parseInt(process.env.MAX_RETRY_ATTEMPTS || '3', 10),
  retryDelayMs: parseInt(process.env.RETRY_DELAY_MS || '1000', 10),
};

// Validation
if (!config.apiSecretToken) {
  throw new Error('API_SECRET_TOKEN is required in .env');
}

if (!config.discordWebhookUrl) {
  throw new Error('DISCORD_WEBHOOK_URL is required in .env');
}
