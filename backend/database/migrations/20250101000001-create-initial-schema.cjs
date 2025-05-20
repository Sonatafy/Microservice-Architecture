'use strict';

/**
 * Migration to create the initial database schema for the microservice
 */

module.exports = {
  async up(queryInterface, Sequelize) {
    // Create Messages table for event log
    await queryInterface.createTable('Messages', {
      id: {
        type: Sequelize.UUID,
        defaultValue: Sequelize.UUIDV4,
        primaryKey: true
      },
      messageId: {
        type: Sequelize.STRING,
        allowNull: false,
        unique: true,
        comment: 'Unique message identifier'
      },
      type: {
        type: Sequelize.STRING,
        allowNull: false,
        comment: 'Message type'
      },
      payload: {
        type: Sequelize.JSONB,
        allowNull: true,
        comment: 'Message payload'
      },
      status: {
        type: Sequelize.ENUM('pending', 'processing', 'completed', 'failed'),
        defaultValue: 'pending'
      },
      processingAttempts: {
        type: Sequelize.INTEGER,
        defaultValue: 0
      },
      error: {
        type: Sequelize.TEXT,
        allowNull: true,
        comment: 'Error information if processing failed'
      },
      // Timestamps
      createdAt: {
        type: Sequelize.DATE,
        allowNull: false
      },
      updatedAt: {
        type: Sequelize.DATE,
        allowNull: false
      },
      deletedAt: {
        type: Sequelize.DATE,
        allowNull: true
      }
    });

    // Create Tasks table for tracking work items
    await queryInterface.createTable('Tasks', {
      id: {
        type: Sequelize.UUID,
        defaultValue: Sequelize.UUIDV4,
        primaryKey: true
      },
      taskId: {
        type: Sequelize.STRING,
        allowNull: false,
        unique: true,
        comment: 'Unique task identifier'
      },
      type: {
        type: Sequelize.STRING,
        allowNull: false,
        comment: 'Task type'
      },
      data: {
        type: Sequelize.JSONB,
        allowNull: true,
        comment: 'Task data'
      },
      status: {
        type: Sequelize.ENUM('pending', 'in_progress', 'completed', 'failed', 'cancelled'),
        defaultValue: 'pending'
      },
      priority: {
        type: Sequelize.INTEGER,
        defaultValue: 0,
        comment: 'Task priority (higher number = higher priority)'
      },
      assignedTo: {
        type: Sequelize.STRING,
        allowNull: true,
        comment: 'Worker ID assigned to this task'
      },
      result: {
        type: Sequelize.JSONB,
        allowNull: true,
        comment: 'Result of task execution'
      },
      errorMessage: {
        type: Sequelize.TEXT,
        allowNull: true,
        comment: 'Error message if task failed'
      },
      retryCount: {
        type: Sequelize.INTEGER,
        defaultValue: 0,
        comment: 'Number of retry attempts'
      },
      nextRetryAt: {
        type: Sequelize.DATE,
        allowNull: true,
        comment: 'When to retry next'
      },
      // Timestamps
      createdAt: {
        type: Sequelize.DATE,
        allowNull: false
      },
      updatedAt: {
        type: Sequelize.DATE,
        allowNull: false
      },
      deletedAt: {
        type: Sequelize.DATE,
        allowNull: true
      }
    });

    // Create indexes for better query performance
    await queryInterface.addIndex('Messages', ['messageId'], { unique: true });
    await queryInterface.addIndex('Messages', ['type']);
    await queryInterface.addIndex('Messages', ['status']);
    
    await queryInterface.addIndex('Tasks', ['taskId'], { unique: true });
    await queryInterface.addIndex('Tasks', ['type']);
    await queryInterface.addIndex('Tasks', ['status']);
    await queryInterface.addIndex('Tasks', ['priority']);
    await queryInterface.addIndex('Tasks', ['assignedTo']);
  },

  async down(queryInterface, Sequelize) {
    // Drop tables in reverse order to avoid foreign key constraints
    await queryInterface.dropTable('Tasks');
    await queryInterface.dropTable('Messages');
  }
};
