// backend/database/models/Task.js
import { DataTypes } from 'sequelize';

export default (sequelize) => {
  const Task = sequelize.define('Task', {
    id: {
      type: DataTypes.UUID,
      defaultValue: DataTypes.UUIDV4,
      primaryKey: true
    },
    taskId: {
      type: DataTypes.STRING,
      allowNull: false,
      unique: true,
      comment: 'Unique task identifier'
    },
    type: {
      type: DataTypes.STRING,
      allowNull: false,
      comment: 'Task type'
    },
    data: {
      type: DataTypes.JSONB,
      allowNull: true,
      comment: 'Task data'
    },
    status: {
      type: DataTypes.ENUM('pending', 'in_progress', 'completed', 'failed', 'cancelled'),
      defaultValue: 'pending'
    },
    priority: {
      type: DataTypes.INTEGER,
      defaultValue: 0,
      comment: 'Task priority (higher number = higher priority)'
    },
    assignedTo: {
      type: DataTypes.STRING,
      allowNull: true,
      comment: 'Worker ID assigned to this task'
    },
    result: {
      type: DataTypes.JSONB,
      allowNull: true,
      comment: 'Result of task execution'
    },
    errorMessage: {
      type: DataTypes.TEXT,
      allowNull: true,
      comment: 'Error message if task failed'
    },
    retryCount: {
      type: DataTypes.INTEGER,
      defaultValue: 0,
      comment: 'Number of retry attempts'
    },
    nextRetryAt: {
      type: DataTypes.DATE,
      allowNull: true,
      comment: 'When to retry next'
    }
  }, {
    timestamps: true,
    paranoid: true,
    indexes: [
      {
        fields: ['taskId'],
        unique: true
      },
      {
        fields: ['type']
      },
      {
        fields: ['status']
      },
      {
        fields: ['priority']
      },
      {
        fields: ['assignedTo']
      }
    ]
  });

  return Task;
};
