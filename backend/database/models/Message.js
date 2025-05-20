// backend/database/models/Message.js
import { DataTypes } from 'sequelize';

export default (sequelize) => {
  const Message = sequelize.define('Message', {
    id: {
      type: DataTypes.UUID,
      defaultValue: DataTypes.UUIDV4,
      primaryKey: true
    },
    messageId: {
      type: DataTypes.STRING,
      allowNull: false,
      unique: true,
      comment: 'Unique message identifier'
    },
    type: {
      type: DataTypes.STRING,
      allowNull: false,
      comment: 'Message type'
    },
    payload: {
      type: DataTypes.JSONB,
      allowNull: true,
      comment: 'Message payload'
    },
    status: {
      type: DataTypes.ENUM('pending', 'processing', 'completed', 'failed'),
      defaultValue: 'pending'
    },
    processingAttempts: {
      type: DataTypes.INTEGER,
      defaultValue: 0
    },
    error: {
      type: DataTypes.TEXT,
      allowNull: true,
      comment: 'Error information if processing failed'
    }
  }, {
    timestamps: true,
    paranoid: true,
    indexes: [
      {
        fields: ['messageId'],
        unique: true
      },
      {
        fields: ['type']
      },
      {
        fields: ['status']
      }
    ]
  });

  return Message;
};
