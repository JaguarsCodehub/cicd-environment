import dotenv from 'dotenv';

// Load environment variables from process.env or .env file if present
dotenv.config();

export const config = {
  env: process.env.NODE_ENV || 'development',
  port: parseInt(process.env.PORT || '3000', 10),
  appName: process.env.APP_NAME || 'cicd-environment-demo',
  version: process.env.APP_VERSION || '1.0.0',
  commitSha: process.env.COMMIT_SHA || process.env.GITHUB_SHA || 'local-dev',
  databaseUrl: process.env.DATABASE_URL || 'postgres://dev_user:dev_pass@localhost:5432/dev_db',
  logLevel: process.env.LOG_LEVEL || 'info',
};
