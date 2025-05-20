import express from 'express';
import cors from 'cors';
import { v4 as uuidv4 } from 'uuid';
import * as amqp from 'amqplib';
import Redis from 'ioredis';
import config from './config.js';

// Create Express app
const app = express();
app.use(cors());
app.use(express.json());

// Add request ID middleware
app.use((req, res, next) => {
  req.id = req.headers['x-request-id'] || uuidv4();
  res.setHeader('X-Request-ID', req.id);
  next();
});

// Add basic logging middleware
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = Date.now() - start;
    console.log(`${req.method} ${req.originalUrl} ${res.statusCode} ${duration}ms [${req.id}]`);
  });
  next();
});

// Create Redis client
const redis = new Redis(config.REDIS_URL || 'redis://redis:6379', {
  keyPrefix: 'api:',
  maxRetriesPerRequest: 3,
  connectTimeout: 5000
});

// Connect to RabbitMQ
let channel;
async function setupRabbitMQ() {
  try {
    console.log('Connecting to RabbitMQ...');
    const connection = await amqp.connect(config.RABBITMQ_URL);
    
    // Create a channel
    channel = await connection.createChannel();
    
    // Ensure queues exist
    await channel.assertQueue(config.QUEUE_TASK_CREATED, { durable: true });
    await channel.assertQueue(config.QUEUE_TASK_COMPLETED, { durable: true });
    
    console.log('RabbitMQ connection established');
    return channel;
  } catch (error) {
    console.error('Error connecting to RabbitMQ:', error);
    console.log('Attempting to reconnect in 5 seconds...');
    setTimeout(setupRabbitMQ, 5000);
  }
}

// API endpoints
app.post('/api/tasks', async (req, res) => {
  try {
    const taskId = uuidv4();
    const task = {
      taskId,
      type: req.body.type || 'default_task',
      data: req.body.data || {},
      status: 'pending',
      createdAt: new Date().toISOString()
    };
    
    // Store the task in Redis for tracking
    await redis.set(`task:${taskId}`, JSON.stringify(task), 'EX', 3600);
    
    // Publish task to RabbitMQ
    await channel.sendToQueue(
      config.QUEUE_TASK_CREATED,
      Buffer.from(JSON.stringify(task)),
      { persistent: true }
    );
    
    res.status(201).json({
      status: 'success',
      taskId,
      message: 'Task created and queued for processing'
    });
  } catch (error) {
    console.error('Error creating task:', error);
    res.status(500).json({
      status: 'error',
      error: 'Failed to create task',
      message: error.message
    });
  }
});

app.get('/api/tasks/:id', async (req, res) => {
  try {
    const taskId = req.params.id;
    const taskJson = await redis.get(`task:${taskId}`);
    
    if (!taskJson) {
      return res.status(404).json({
        status: 'error',
        error: 'Task not found'
      });
    }
    
    const task = JSON.parse(taskJson);
    res.json({
      status: 'success',
      task
    });
  } catch (error) {
    console.error(`Error fetching task ${req.params.id}:`, error);
    res.status(500).json({
      status: 'error',
      error: 'Failed to fetch task',
      message: error.message
    });
  }
});

// Health check endpoint
app.get('/health', async (req, res) => {
  // Check Redis connection
  let redisStatus = 'disconnected';
  try {
    const pingResult = await redis.ping();
    redisStatus = pingResult === 'PONG' ? 'connected' : 'error';
  } catch (redisError) {
    redisStatus = 'error';
  }
  
  // Check RabbitMQ status
  const rabbitmqStatus = channel ? 'connected' : 'disconnected';
  
  res.json({ 
    status: redisStatus === 'connected' && rabbitmqStatus === 'connected' ? 'ok' : 'degraded', 
    timestamp: new Date().toISOString(),
    instanceId: process.env.HOSTNAME || 'unknown'
  });
});

// Start the server
async function startServer() {
  try {
    // Connect to RabbitMQ
    await setupRabbitMQ();
    
    // Start the API server
    app.listen(config.PORT, () => {
      console.log(`API Service running on port ${config.PORT}`);
      console.log(`Instance ID: ${process.env.HOSTNAME || 'unknown'}`);
    });
  } catch (error) {
    console.error('Failed to start services:', error);
    process.exit(1);
  }
}

// Start the server
startServer();

// Error handling
process.on('uncaughtException', (error) => {
  console.error('Uncaught Exception:', error);
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
});

export { app, redis };
