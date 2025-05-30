// backend/database/index.js
import { Sequelize } from 'sequelize';
import { fileURLToPath } from 'url';
import { createRequire } from 'module';
import path from 'path';
import dotenv from 'dotenv';

// Load environment variables
dotenv.config();

// Get __dirname equivalent in ESM
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Create require function to import CommonJS modules
const require = createRequire(import.meta.url);

// Import the CommonJS config file
const configPath = path.join(__dirname, 'config', 'config.cjs');
const configs = require(configPath);
const env = process.env.NODE_ENV || 'development';
const config = configs[env];

// Import model definitions
import defineMessageModel from './models/Message.js';
import defineTaskModel from './models/Task.js';

// Create Sequelize instance with proper error handling
let sequelize;
try {
  sequelize = new Sequelize(
    config.database, 
    config.username, 
    config.password, 
    {
      host: config.host,
      port: config.port,
      dialect: config.dialect,
      logging: config.logging || false,
      dialectOptions: config.dialectOptions || {},
      pool: config.pool || {
        max: 5,
        min: 0,
        acquire: 30000,
        idle: 10000
      }
    }
  );
} catch (error) {
  console.error('Failed to create Sequelize instance:', error);
  throw error;
}

// Define models
const models = {
  Message: defineMessageModel(sequelize),
  Task: defineTaskModel(sequelize),
};

// Set up model associations
Object.keys(models).forEach(modelName => {
  if (models[modelName].associate) {
    models[modelName].associate(models);
  }
});

// Test database connection
async function testConnection() {
  try {
    await sequelize.authenticate();
    console.log(`Database connection established successfully to ${config.database} on ${config.host}:${config.port}`);
    return true;
  } catch (error) {
    console.error('Unable to connect to the database:', error);
    
    // Log helpful message about database not existing
    if (error.message && error.message.includes('database') && error.message.includes('does not exist')) {
      console.error(`\n==============================================================`);
      console.error(`ERROR: Database '${config.database}' does not exist`);
      console.error(`\nTo create the database, you can run:`);
      console.error(`  docker-compose exec postgres createdb -U ${config.username} ${config.database}`);
      console.error(`Or make sure the database migrations have been run.`);
      console.error(`==============================================================\n`);
    }
    
    return false;
  }
}

// Initialize database models (sync in development only)
async function initializeDatabase() {
  if (process.env.NODE_ENV === 'development') {
    try {
      // Test connection first
      const connected = await testConnection();
      if (!connected) {
        console.warn('Database connection failed, models may not work properly');
        return false;
      }
      
      // In development, we can auto-sync models (be careful in production!)
      // This will create tables if they don't exist, but won't run migrations
      console.log('Synchronizing database models...');
      await sequelize.sync({ alter: false }); // Set to true only if you want to auto-alter tables
      console.log('Database models synchronized successfully');
      return true;
    } catch (error) {
      console.error('Error synchronizing database models:', error);
      return false;
    }
  } else {
    // In production, just test the connection
    return await testConnection();
  }
}

// Export the db object
export {
  sequelize,
  Sequelize,
  models,
  testConnection,
  initializeDatabase,
  config
};