// backend/src/controllers/tasksController.js
import express from 'express';
import { v4 as uuidv4 } from 'uuid';
import { models } from '../../database/index.js';

const router = express.Router();
const { Task } = models;

/**
 * @swagger
 * /tasks:
 *   get:
 *     summary: Get a list of all tasks
 *     description: Returns a paginated list of all tasks
 *     tags: [Tasks]
 *     parameters:
 *       - in: query
 *         name: page
 *         schema:
 *           type: integer
 *           default: 1
 *         description: Page number
 *       - in: query
 *         name: limit
 *         schema:
 *           type: integer
 *           default: 50
 *         description: Number of items per page
 *       - in: query
 *         name: status
 *         schema:
 *           type: string
 *           enum: [pending, in_progress, completed, failed, cancelled]
 *         description: Filter by task status
 *     responses:
 *       200:
 *         description: List of tasks successfully retrieved
 *       500:
 *         description: Server error
 */
router.get('/', async (req, res) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 50;
    const offset = (page - 1) * limit;
    const status = req.query.status;

    // Build where clause based on query params
    const where = {};
    if (status) {
      where.status = status;
    }

    const { count, rows } = await Task.findAndCountAll({
      where,
      order: [['createdAt', 'DESC']],
      limit,
      offset
    });

    res.json({
      status: 'success',
      tasks: rows,
      pagination: {
        total: count,
        page,
        limit,
        pages: Math.ceil(count / limit)
      }
    });
  } catch (error) {
    console.error('Error fetching tasks:', error);
    res.status(500).json({
      status: 'error',
      error: 'Failed to fetch tasks',
      message: error.message
    });
  }
});

/**
 * @swagger
 * /tasks/{id}:
 *   get:
 *     summary: Get task details by ID
 *     description: Retrieves details for a specific task
 *     tags: [Tasks]
 *     parameters:
 *       - in: path
 *         name: id
 *         required: true
 *         description: Task ID to retrieve
 *         schema:
 *           type: string
 *     responses:
 *       200:
 *         description: Task details successfully retrieved
 *       404:
 *         description: Task not found
 *       500:
 *         description: Server error
 */
router.get('/:id', async (req, res) => {
  try {
    const task = await Task.findOne({
      where: { taskId: req.params.id }
    });

    if (!task) {
      return res.status(404).json({
        status: 'error',
        error: 'Task not found'
      });
    }

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

/**
 * @swagger
 * /tasks:
 *   post:
 *     summary: Create a new task
 *     description: Creates a new task with the provided data
 *     tags: [Tasks]
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required:
 *               - type
 *               - data
 *             properties:
 *               type:
 *                 type: string
 *                 description: Type of task to create
 *               data:
 *                 type: object
 *                 description: Task data
 *               priority:
 *                 type: integer
 *                 description: Task priority (higher = more priority)
 *                 default: 0
 *     responses:
 *       201:
 *         description: Task created successfully
 *       400:
 *         description: Bad request, validation error
 *       500:
 *         description: Server error
 */
router.post('/', async (req, res) => {
  try {
    const { type, data, priority = 0 } = req.body;

    if (!type) {
      return res.status(400).json({
        status: 'error',
        error: 'Task type is required'
      });
    }

    if (!data) {
      return res.status(400).json({
        status: 'error',
        error: 'Task data is required'
      });
    }

    const task = await Task.create({
      taskId: uuidv4(),
      type,
      data,
      priority,
      status: 'pending'
    });

    res.status(201).json({
      status: 'success',
      task,
      message: 'Task created successfully'
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

/**
 * @swagger
 * /tasks/{id}:
 *   put:
 *     summary: Update a task
 *     description: Updates an existing task with the provided data
 *     tags: [Tasks]
 *     parameters:
 *       - in: path
 *         name: id
 *         required: true
 *         description: Task ID to update
 *         schema:
 *           type: string
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             properties:
 *               status:
 *                 type: string
 *                 enum: [pending, in_progress, completed, failed, cancelled]
 *               data:
 *                 type: object
 *                 description: Updated task data
 *               result:
 *                 type: object
 *                 description: Task result data
 *               priority:
 *                 type: integer
 *                 description: Updated task priority
 *     responses:
 *       200:
 *         description: Task updated successfully
 *       404:
 *         description: Task not found
 *       500:
 *         description: Server error
 */
router.put('/:id', async (req, res) => {
  try {
    const { status, data, result, priority } = req.body;
    
    const task = await Task.findOne({
      where: { taskId: req.params.id }
    });

    if (!task) {
      return res.status(404).json({
        status: 'error',
        error: 'Task not found'
      });
    }

    // Update only provided fields
    const updates = {};
    if (status !== undefined) updates.status = status;
    if (data !== undefined) updates.data = data;
    if (result !== undefined) updates.result = result;
    if (priority !== undefined) updates.priority = priority;

    await task.update(updates);

    res.json({
      status: 'success',
      task,
      message: 'Task updated successfully'
    });
  } catch (error) {
    console.error(`Error updating task ${req.params.id}:`, error);
    res.status(500).json({
      status: 'error',
      error: 'Failed to update task',
      message: error.message
    });
  }
});

export default router;
