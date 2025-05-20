// backend/database/index.js
import { Sequelize } from 'sequelize';
import { fileURLToPath } from 'url';
import path from 'path';
import dotenv from 'dotenv';
import config from './config/config.js';

// Load environment variables
dotenv.config();

// Get __dirname equivalent in ESM
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Import model definitions
import defineMessageModel from './models/Message.js';
import defineTaskModel from './models/Task.js';

// Create Sequelize instance
const sequelize = new Sequelize(
  config.database, 
  config.username, 
  config.password, 
  {
    host: config.host,
    port: config.port,
    dialect: config.dialect,
    logging: config.logging,
    dialectOptions: config.dialectOptions,
    pool: config.pool
  }
);

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
    console.log('Database connection has been established successfully.');
    return true;
  } catch (error) {
    console.error('Unable to connect to the database:', error);
    
    // Log helpful message about database not existing
    if (error.message && error.message.includes('database') && error.message.includes('does not exist')) {
      console.error(`\n==============================================================`);
      console.error(`ERROR: Database '${config.database}' does not exist`);
      console.error(`\nMake sure the database has been created.`);
      console.error(`==============================================================\n`);
    }
    
    return false;
  }
}

// Export the db object
export {
  sequelize,
  Sequelize,
  models,
  testConnection
};
