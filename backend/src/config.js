import 'dotenv/config';

export default {
  PORT: process.env.PORT || 3000,
  
  // RabbitMQ configuration
  RABBITMQ_URL: process.env.RABBITMQ_URL || 'amqp://guest:guest@rabbitmq:5672',
  QUEUE_TASK_CREATED: 'task-created',
  QUEUE_TASK_COMPLETED: 'task-completed',
  
  // Redis configuration
  REDIS_URL: process.env.REDIS_URL || 'redis://redis:6379',

  // Database configuration
  DB_DIALECT: process.env.DB_DIALECT || 'postgres',
  DB_HOST: process.env.DB_HOST || 'postgres',
  DB_PORT: parseInt(process.env.DB_PORT || '5432', 10),
  DB_USERNAME: process.env.DB_USERNAME || 'microservice',
  DB_PASSWORD: process.env.DB_PASSWORD || 'microservice_password',
  DB_NAME: process.env.DB_NAME || 'microservice_db'
};
