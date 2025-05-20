// backend/src/services/queueMonitorService.js
import * as amqp from 'amqplib';
import { exec } from 'child_process';
import { promisify } from 'util';
import config from '../config.js';

const execPromise = promisify(exec);

/**
 * Service for monitoring queue depths and auto-scaling worker processes
 */
class QueueMonitorService {
  constructor(options = {}) {
    this.rabbitMqUrl = options.rabbitMqUrl || config.RABBITMQ_URL;
    this.queues = options.queues || [
      config.QUEUE_TASK_CREATED,
      config.QUEUE_TASK_COMPLETED
    ];
    this.checkInterval = options.checkInterval || 10000; // Default: check every 10 seconds
    this.scaleUpThreshold = options.scaleUpThreshold || 10; // Scale up when queue depth reaches this value
    this.scaleDownThreshold = options.scaleDownThreshold || 2; // Scale down when queue depth falls below this value
    this.maxWorkers = options.maxWorkers || 5; // Maximum number of worker processes
    this.minWorkers = options.minWorkers || 1; // Minimum number of worker processes
    this.isRunning = false;
    this.checkTimer = null;
    this.connection = null;
    this.channel = null;
    this.dockerMode = process.env.DOCKER_SCALE === 'true';
    this.currentWorkerCount = this.minWorkers; // Start with minimum workers
  }

  /**
   * Start the queue monitor service
   */
  async start() {
    if (this.isRunning) {
      console.log('Queue monitor service is already running');
      return;
    }

    try {
      console.log('Starting queue monitor service...');
      console.log(`Docker mode: ${this.dockerMode ? 'enabled' : 'disabled'}`);
      
      // Connect to RabbitMQ
      this.connection = await amqp.connect(this.rabbitMqUrl);
      this.channel = await this.connection.createChannel();
      
      // Set up monitoring interval
      this.checkTimer = setInterval(() => this.checkQueueDepths(), this.checkInterval);
      this.isRunning = true;
      
      // Start minimum number of workers
      await this.ensureMinimumWorkers();
      
      // Handle connection close
      this.connection.on('close', async (err) => {
        console.error('Queue monitor: RabbitMQ connection closed', err);
        clearInterval(this.checkTimer);
        this.isRunning = false;
        
        // Attempt to reconnect
        console.log('Queue monitor: Attempting to reconnect in 5 seconds...');
        setTimeout(() => this.start(), 5000);
      });
      
      console.log('Queue monitor service started successfully');
    } catch (error) {
      console.error('Error starting queue monitor service:', error);
      
      // Clean up if error during startup
      if (this.connection) {
        try {
          await this.connection.close();
        } catch (closeError) {
          console.error('Error closing connection:', closeError);
        }
      }
      
      this.isRunning = false;
      
      // Attempt to restart
      console.log('Queue monitor: Attempting to restart in 5 seconds...');
      setTimeout(() => this.start(), 5000);
    }
  }

  /**
   * Stop the queue monitor service
   */
  async stop() {
    if (!this.isRunning) {
      console.log('Queue monitor service is not running');
      return;
    }

    console.log('Stopping queue monitor service...');
    
    clearInterval(this.checkTimer);
    this.checkTimer = null;
    
    try {
      if (this.connection) {
        await this.connection.close();
      }
    } catch (error) {
      console.error('Error closing connection:', error);
    }
    
    this.isRunning = false;
    console.log('Queue monitor service stopped');
  }

  /**
   * Check the depth of all monitored queues
   */
  async checkQueueDepths() {
    if (!this.isRunning || !this.channel) return;
    
    try {
      let totalMessages = 0;
      
      // Check each queue and sum the total messages
      for (const queueName of this.queues) {
        const queueInfo = await this.channel.assertQueue(queueName, { durable: true });
        const messageCount = queueInfo.messageCount;
        totalMessages += messageCount;
        
        console.log(`Queue ${queueName}: ${messageCount} messages`);
      }
      
      console.log(`Total messages across all queues: ${totalMessages}`);
      
      // Determine if scaling is needed
      if (totalMessages > this.scaleUpThreshold && this.currentWorkerCount < this.maxWorkers) {
        // Scale up: add more workers
        await this.scaleUp(Math.min(
          this.maxWorkers - this.currentWorkerCount,
          Math.ceil(totalMessages / this.scaleUpThreshold)
        ));
      } else if (totalMessages < this.scaleDownThreshold && this.currentWorkerCount > this.minWorkers) {
        // Scale down: remove excess workers
        await this.scaleDown(Math.min(
          this.currentWorkerCount - this.minWorkers,
          Math.ceil((this.scaleDownThreshold - totalMessages) / this.scaleDownThreshold)
        ));
      }
    } catch (error) {
      console.error('Error checking queue depths:', error);
    }
  }

  /**
   * Ensure the minimum number of workers are running
   */
  async ensureMinimumWorkers() {
    try {
      if (this.dockerMode) {
        // For Docker, check current scale
        const { stdout } = await execPromise('docker-compose ps -q worker-service | wc -l');
        const currentWorkers = parseInt(stdout.trim(), 10);
        this.currentWorkerCount = currentWorkers;
        
        if (currentWorkers < this.minWorkers) {
          await this.scaleUp(this.minWorkers - currentWorkers);
        }
      } else {
        // In non-Docker mode, scale to minimum directly
        if (this.currentWorkerCount < this.minWorkers) {
          await this.scaleUp(this.minWorkers - this.currentWorkerCount);
        }
      }
    } catch (error) {
      console.error('Error ensuring minimum workers:', error);
    }
  }

  /**
   * Scale up by starting new worker processes
   * @param {number} count - Number of workers to add
   */
  async scaleUp(count) {
    console.log(`Scaling up: adding ${count} workers`);
    
    try {
      if (this.dockerMode) {
        // For Docker environments, use docker-compose scale
        const targetWorkers = this.currentWorkerCount + count;
        console.log(`Scaling worker-service to ${targetWorkers} workers via Docker`);
        
        // Using docker-compose with deploy mode needs service update
        const { stdout, stderr } = await execPromise(
          `docker-compose up -d --scale worker-service=${targetWorkers}`
        );
        
        console.log('Scale up output:', stdout);
        if (stderr) {
          console.error('Scale up error:', stderr);
        }
        
        this.currentWorkerCount = targetWorkers;
        console.log(`New worker count: ${this.currentWorkerCount}`);
      } else {
        console.log('Non-Docker scaling not implemented in this version');
        // For local environment, we would spawn new processes here
        this.currentWorkerCount += count;
      }
    } catch (error) {
      console.error('Error scaling up workers:', error);
    }
  }

  /**
   * Scale down by stopping excess worker processes
   * @param {number} count - Number of workers to remove
   */
  async scaleDown(count) {
    if (this.currentWorkerCount <= this.minWorkers) return;
    
    const actualCount = Math.min(count, this.currentWorkerCount - this.minWorkers);
    console.log(`Scaling down: removing ${actualCount} workers`);
    
    try {
      if (this.dockerMode) {
        // For Docker environments, use docker-compose scale
        const targetWorkers = this.currentWorkerCount - actualCount;
        console.log(`Scaling worker-service to ${targetWorkers} workers via Docker`);
        
        const { stdout, stderr } = await execPromise(
          `docker-compose up -d --scale worker-service=${targetWorkers}`
        );
        
        console.log('Scale down output:', stdout);
        if (stderr) {
          console.error('Scale down error:', stderr);
        }
        
        this.currentWorkerCount = targetWorkers;
        console.log(`New worker count: ${this.currentWorkerCount}`);
      } else {
        console.log('Non-Docker scaling not implemented in this version');
        // For local environment, we would stop processes here
        this.currentWorkerCount -= actualCount;
      }
    } catch (error) {
      console.error('Error scaling down workers:', error);
    }
  }
}

export default QueueMonitorService;
