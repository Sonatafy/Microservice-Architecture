'use strict';

// This file is used by sequelize-cli for migrations
// CommonJS format is needed for Sequelize CLI
require('dotenv').config();

// Common configuration
const baseConfig = {
  dialect: process.env.DB_DIALECT || 'postgres',
  host: process.env.DB_HOST || 'postgres',
  port: parseInt(process.env.DB_PORT || '5432', 10),
  username: process.env.DB_USERNAME,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME || 'microservice_db',
  // Use sequelize_migrations table instead of SequelizeMeta
  migrationStorageTableName: 'sequelize_migrations',
  seederStorageTableName: 'sequelize_seeders',
  seederStorage: 'sequelize',
};

module.exports = {
  development: {
    ...baseConfig,
    logging: console.log,
  },
  test: {
    dialect: 'sqlite',
    storage: ':memory:',
    logging: false,
    migrationStorageTableName: 'sequelize_migrations',
    seederStorageTableName: 'sequelize_seeders'
  },
  production: {
    ...baseConfig,
    logging: false,
    dialectOptions: process.env.DB_SSL === 'true' ? {
      ssl: {
        require: true,
        rejectUnauthorized: process.env.DB_SSL_REJECT_UNAUTHORIZED !== 'false'
      }
    } : {},
    pool: {
      max: 5,
      min: 0,
      acquire: 30000,
      idle: 10000
    }
  }
};
