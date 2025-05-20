import * as amqp from 'amqplib';
import Redis from 'ioredis';
import config from '../config.js';

// Worker configuration
const WORKER_CONCURRENCY = parseInt(process.env.WORKER_CONCURRENCY || '3', 10);
const WORKER_ID = process.env.WORKER_ID || `worker-${process.pid}`;

// Track active jobs
let activeJobs = 0;

// Initialize Redis client
const redis = new Redis(config.REDIS_URL || 'redis://redis:6379', {
  keyPrefix: 'worker:',
  maxRetriesPerRequest: 3,
  connectTimeout: 5000
});

/**
 * Start the worker service
 */
async function startWorkerService() {
  try {
    console.log(`Worker Service [${WORKER_ID}]: Starting with concurrency ${WORKER_CONCURRENCY}`);
    
    // Connect to RabbitMQ
    const connection = await amqp.connect(config.RABBITMQ_URL);
    const channel = await connection.createChannel();

    // Set prefetch based on concurrency
    channel.prefetch(WORKER_CONCURRENCY);
    
    // Ensure queues exist
    await channel.assertQueue(config.QUEUE_TASK_CREATED, { durable: true });
    await channel.assertQueue(config.QUEUE_TASK_COMPLETED, { durable: true });
    
    // Process messages from task-created queue
    await channel.consume(config.QUEUE_TASK_CREATED, async (msg) => {
      if (msg !== null) {
        activeJobs++;
        const startTime = Date.now();
        
        try {
          const data = JSON.parse(msg.content.toString());
          const taskId = data.taskId;
          
          console.log(`Processing task: ${taskId}`);
          
          // Check if this task is already being processed
          const processingKey = `processing:${taskId}`;
          const isBeingProcessed = await redis.exists(processingKey);
          
          if (isBeingProcessed) {
            console.log(`Task ${taskId} is already being processed - skipping`);
            channel.ack(msg);
            activeJobs--;
            return;
          }
          
          // Mark this task as being processed
          await redis.set(processingKey, WORKER_ID, 'EX', 60);
          
          // Update task status in Redis
          const taskJson = await redis.get(`task:${taskId}`);
          if (taskJson) {
            const task = JSON.parse(taskJson);
            task.status = 'processing';
            task.assignedTo = WORKER_ID;
            task.processingStartedAt = new Date().toISOString();
            await redis.set(`task:${taskId}`, JSON.stringify(task), 'EX', 3600);
          }
          
          // Process the task (example implementation)
          const result = await processTask(data);
          
          // Update task with result
          if (taskJson) {
            const task = JSON.parse(taskJson);
            task.status = 'completed';
            task.result = result;
            task.completedAt = new Date().toISOString();
            await redis.set(`task:${taskId}`, JSON.stringify(task), 'EX', 3600);
          }
          
          // Publish completion event
          await channel.sendToQueue(
            config.QUEUE_TASK_COMPLETED,
            Buffer.from(JSON.stringify({
              taskId,
              result,
              workerId: WORKER_ID,
              timestamp: new Date().toISOString()
            })),
            { persistent: true }
          );
          
          // Acknowledge the message
          channel.ack(msg);
          
          // Clean up Redis processing marker
          await redis.del(processingKey);
          
          console.log(`Task ${taskId} completed successfully`);
        } catch (error) {
          console.error(`Error processing message:`, error);
          
          // Either retry or acknowledge the message
          channel.nack(msg, false, true); // Requeue the message
        } finally {
          activeJobs--;
          const processingTime = Date.now() - startTime;
          console.log(`Processing took ${processingTime}ms, active jobs: ${activeJobs}`);
        }
      }
    });
    
    console.log(`Worker Service [${WORKER_ID}] started and ready to process tasks`);
    return { connection, channel };
  } catch (error) {
    console.error('Worker Service: Error starting service:', error);
    console.log('Attempting to restart in 5 seconds...');
    setTimeout(startWorkerService, 5000);
    return null;
  }
}

/**
 * Process a task (example implementation)
 * @param {Object} task - Task data
 * @returns {Promise<Object>} Processing result
 */
async function processTask(task) {
  // For demonstration - simulate processing time
  await new Promise(resolve => setTimeout(resolve, 2000));
  
  // Handle different task types
  switch (task.type) {
    case 'example_task':
      return {
        processed: true,
        message: `Task ${task.taskId} processed successfully`,
        timestamp: new Date().toISOString()
      };
    default:
      return {
        processed: true,
        message: `Processed task of type ${task.type}`,
        timestamp: new Date().toISOString()
      };
  }
}

// Handle shutdown gracefully
async function gracefulShutdown(connection) {
  console.log(`Worker Service [${WORKER_ID}]: Shutting down...`);
  
  // Wait for active jobs to complete (up to 10 seconds)
  const maxWaitTime = 10000;
  const startTime = Date.now();
  
  while (activeJobs > 0 && (Date.now() - startTime) < maxWaitTime) {
    console.log(`Waiting for ${activeJobs} active jobs to complete...`);
    await new Promise(resolve => setTimeout(resolve, 500));
  }
  
  // Close connections
  try {
    await connection.close();
    await redis.quit();
  } catch (error) {
    console.error('Error during shutdown:', error);
  }
  
  console.log('Worker service shutdown complete');
}

// Start the worker service
const workerPromise = startWorkerService();

// Handle termination signals
process.on('SIGTERM', async () => {
  console.log('SIGTERM received, shutting down worker...');
  const { connection } = await workerPromise;
  await gracefulShutdown(connection);
  process.exit(0);
});

process.on('SIGINT', async () => {
  console.log('SIGINT received, shutting down worker...');
  const { connection } = await workerPromise;
  await gracefulShutdown(connection);
  process.exit(0);
});
