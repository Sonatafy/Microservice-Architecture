// backend/src/services/queueMonitorStarter.js
import QueueMonitorService from './queueMonitorService.js';
import config from '../config.js';

/**
 * Starter script for the Queue Monitor Service
 * This file is the entry point for the queue-monitor container
 */

// Configuration from environment variables
const monitorConfig = {
  rabbitMqUrl: config.RABBITMQ_URL,
  queues: [
    config.QUEUE_TASK_CREATED,
    config.QUEUE_TASK_COMPLETED
  ],
  checkInterval: parseInt(process.env.CHECK_INTERVAL || '10000', 10),
  scaleUpThreshold: parseInt(process.env.SCALE_UP_THRESHOLD || '10', 10),
  scaleDownThreshold: parseInt(process.env.SCALE_DOWN_THRESHOLD || '2', 10),
  maxWorkers: parseInt(process.env.MAX_WORKERS || '5', 10),
  minWorkers: parseInt(process.env.MIN_WORKERS || '1', 10)
};

console.log('Queue Monitor Starter: Initializing...');
console.log('Configuration:', {
  ...monitorConfig,
  rabbitMqUrl: monitorConfig.rabbitMqUrl.replace(/\/\/.*@/, '//***:***@') // Hide credentials in logs
});

// Create and start the queue monitor service
const queueMonitor = new QueueMonitorService(monitorConfig);

// Start the service
async function startMonitor() {
  try {
    console.log('Queue Monitor Starter: Starting queue monitor service...');
    await queueMonitor.start();
    console.log('Queue Monitor Starter: Service started successfully');
  } catch (error) {
    console.error('Queue Monitor Starter: Failed to start service:', error);
    console.log('Queue Monitor Starter: Retrying in 10 seconds...');
    setTimeout(startMonitor, 10000);
  }
}

// Handle graceful shutdown
async function gracefulShutdown(signal) {
  console.log(`Queue Monitor Starter: Received ${signal}, shutting down gracefully...`);
  
  try {
    await queueMonitor.stop();
    console.log('Queue Monitor Starter: Shutdown complete');
    process.exit(0);
  } catch (error) {
    console.error('Queue Monitor Starter: Error during shutdown:', error);
    process.exit(1);
  }
}

// Register signal handlers for graceful shutdown
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
  console.error('Queue Monitor Starter: Uncaught Exception:', error);
  gracefulShutdown('uncaughtException');
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('Queue Monitor Starter: Unhandled Rejection at:', promise, 'reason:', reason);
  gracefulShutdown('unhandledRejection');
});

// Start the monitor
startMonitor();