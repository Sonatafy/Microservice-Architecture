// backend/src/swagger.js
import swaggerJsdoc from 'swagger-jsdoc';
import swaggerUi from 'swagger-ui-express';

const options = {
  definition: {
    openapi: '3.0.0',
    info: {
      title: 'Microservice Architecture API',
      version: '1.0.0',
      description: 'Event-driven microservice architecture API documentation',
      contact: {
        name: 'API Support',
        email: 'support@example.com'
      }
    },
    servers: [
      {
        url: 'http://localhost:3001',
        description: 'Development server (direct)'
      },
      {
        url: 'http://localhost:3000',
        description: 'Development server via nginx'
      }
    ],
    components: {
      schemas: {
        Task: {
          type: 'object',
          required: ['taskId', 'type', 'status'],
          properties: {
            id: {
              type: 'string',
              format: 'uuid',
              description: 'Internal task ID'
            },
            taskId: {
              type: 'string',
              description: 'Unique task identifier'
            },
            type: {
              type: 'string',
              description: 'Type of task'
            },
            data: {
              type: 'object',
              description: 'Task data payload'
            },
            status: {
              type: 'string',
              enum: ['pending', 'in_progress', 'completed', 'failed', 'cancelled'],
              description: 'Current task status'
            },
            priority: {
              type: 'integer',
              description: 'Task priority (higher number = higher priority)',
              default: 0
            },
            assignedTo: {
              type: 'string',
              description: 'Worker ID assigned to this task'
            },
            result: {
              type: 'object',
              description: 'Task execution result'
            },
            errorMessage: {
              type: 'string',
              description: 'Error message if task failed'
            },
            retryCount: {
              type: 'integer',
              description: 'Number of retry attempts',
              default: 0
            },
            createdAt: {
              type: 'string',
              format: 'date-time',
              description: 'Task creation timestamp'
            },
            updatedAt: {
              type: 'string',
              format: 'date-time',
              description: 'Task last update timestamp'
            }
          }
        },
        CreateTaskRequest: {
          type: 'object',
          required: ['type', 'data'],
          properties: {
            type: {
              type: 'string',
              description: 'Type of task to create',
              example: 'example_task'
            },
            data: {
              type: 'object',
              description: 'Task data payload',
              example: {
                message: 'Hello World',
                priority: 'high'
              }
            },
            priority: {
              type: 'integer',
              description: 'Task priority',
              default: 0,
              example: 5
            }
          }
        },
        TaskResponse: {
          type: 'object',
          properties: {
            status: {
              type: 'string',
              example: 'success'
            },
            taskId: {
              type: 'string',
              description: 'Created task ID'
            },
            message: {
              type: 'string',
              example: 'Task created and queued for processing'
            }
          }
        },
        HealthResponse: {
          type: 'object',
          properties: {
            status: {
              type: 'string',
              enum: ['ok', 'degraded'],
              example: 'ok'
            },
            timestamp: {
              type: 'string',
              format: 'date-time'
            },
            instanceId: {
              type: 'string',
              example: 'api-service-1'
            },
            services: {
              type: 'object',
              properties: {
                redis: {
                  type: 'string',
                  enum: ['connected', 'disconnected', 'error']
                },
                rabbitmq: {
                  type: 'string',
                  enum: ['connected', 'disconnected', 'error']
                }
              }
            }
          }
        },
        ErrorResponse: {
          type: 'object',
          properties: {
            status: {
              type: 'string',
              example: 'error'
            },
            error: {
              type: 'string',
              example: 'Task not found'
            },
            message: {
              type: 'string',
              example: 'The requested task could not be found'
            }
          }
        }
      }
    }
  },
  apis: [
    './src/index.js',
    './src/controllers/*.js',
    './src/routes/*.js'
  ]
};

const specs = swaggerJsdoc(options);

export { specs };

export function setupSwagger(app) {
  // Swagger UI options
  const swaggerOptions = {
    explorer: true,
    customCss: '.swagger-ui .topbar { display: none }',
    customSiteTitle: 'Microservice API Docs',
    swaggerOptions: {
      persistAuthorization: true,
      displayRequestDuration: true
    }
  };

  // Serve swagger docs
  app.use('/api-docs', swaggerUi.serve, swaggerUi.setup(specs, swaggerOptions));
  
  // API docs JSON endpoint
  app.get('/api-docs.json', (req, res) => {
    res.setHeader('Content-Type', 'application/json');
    res.send(specs);
  });

  console.log('📚 API Documentation available at /api-docs');
  console.log('📄 API JSON specification available at /api-docs.json');
}