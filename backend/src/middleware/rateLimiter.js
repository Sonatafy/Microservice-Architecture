// backend/src/middleware/rateLimiter.js
import Redis from 'ioredis';
import config from '../config.js';

// Default options
const DEFAULT_OPTIONS = {
  windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS || '60000', 10), // Default: 1 minute
  max: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS || '100', 10), // Default: 100 requests per window
  standardHeaders: true, // Return rate limit info in the `RateLimit-*` headers
  legacyHeaders: false, // Do not send the `X-RateLimit-*` headers
  skipSuccessfulRequests: false, // Count all requests toward the rate limit
  requestPropertyName: 'rateLimit', // Will be attached to req object
  message: 'Too many requests, please try again later',
  statusCode: 429, // Standard rate limiting status code
  skipFailedRequests: false, // Count failed requests toward the rate limit
  keyGenerator: (req) => {
    // By default, use IP address as the rate limiter key
    return req.ip || 
           req.headers['x-forwarded-for'] || 
           req.socket.remoteAddress || 
           'unknown';
  },
  // Redis connection options
  redisUrl: config.REDIS_URL || 'redis://localhost:6379',
  redisPrefix: 'rl:', // Redis key prefix for rate limiter
  redisTimeout: 5000, // Redis connection timeout in ms
};

/**
 * Create a Redis-based rate limiter middleware
 * @param {Object} options - Rate limiter options
 * @returns {Function} Express middleware function
 */
export default function createRateLimiter(options = {}) {
  // Merge default options with provided options
  const opts = { ...DEFAULT_OPTIONS, ...options };
  
  // Create Redis client
  const redisClient = new Redis(opts.redisUrl, {
    connectTimeout: opts.redisTimeout,
    maxRetriesPerRequest: 3,
    keyPrefix: opts.redisPrefix
  });
  
  // Handle Redis errors
  redisClient.on('error', (err) => {
    console.error('Redis rate limiter error:', err);
  });
  
  /**
   * Rate limiter middleware function
   * @param {Object} req - Express request object
   * @param {Object} res - Express response object
   * @param {Function} next - Express next function
   */
  return async function rateLimiter(req, res, next) {
    // Skip rate limiting for certain paths or methods if needed
    if (req.path === '/health' || req.path === '/api-docs') {
      return next();
    }
    
    try {
      // Generate rate limiter key
      const key = typeof opts.keyGenerator === 'function' 
        ? opts.keyGenerator(req) 
        : DEFAULT_OPTIONS.keyGenerator(req);
      
      // Convert window from milliseconds to seconds for Redis TTL
      const windowSeconds = Math.ceil(opts.windowMs / 1000);
      
      // Execute Redis commands in a transaction
      const [currentCount, resetTime] = await redisClient.multi()
        // Increment counter for this key
        .incr(key)
        // Set expiration if this is a new key
        .pttl(key)
        .exec()
        .then(results => {
          const count = results[0][1];
          let resetTime = results[1][1];
          
          // If this is a new key (no TTL), set the expiration
          if (resetTime === -1 || resetTime === -2) {
            redisClient.expire(key, windowSeconds);
            resetTime = Date.now() + opts.windowMs;
          } else {
            // Convert PTTL from milliseconds to absolute timestamp
            resetTime = Date.now() + resetTime;
          }
          
          return [count, resetTime];
        });
      
      // Add rate limit info to request object
      req[opts.requestPropertyName] = {
        limit: opts.max,
        current: currentCount,
        remaining: Math.max(0, opts.max - currentCount),
        resetTime: new Date(resetTime)
      };
      
      // Add headers if enabled
      if (opts.standardHeaders) {
        res.setHeader('RateLimit-Limit', opts.max);
        res.setHeader('RateLimit-Remaining', Math.max(0, opts.max - currentCount));
        res.setHeader('RateLimit-Reset', Math.ceil(resetTime / 1000)); // In seconds
      }
      
      if (opts.legacyHeaders) {
        res.setHeader('X-RateLimit-Limit', opts.max);
        res.setHeader('X-RateLimit-Remaining', Math.max(0, opts.max - currentCount));
        res.setHeader('X-RateLimit-Reset', Math.ceil(resetTime / 1000)); // In seconds
      }
      
      // Check if rate limit is exceeded
      if (currentCount > opts.max) {
        if (opts.standardHeaders) {
          res.setHeader('Retry-After', Math.ceil((resetTime - Date.now()) / 1000)); // In seconds
        }
        
        return res.status(opts.statusCode).json({
          error: opts.message,
          retryAfter: Math.ceil((resetTime - Date.now()) / 1000)
        });
      }
      
      // Continue to next middleware
      next();
    } catch (error) {
      console.error('Rate limiter error:', error);
      
      // Fallback: continue to next middleware if rate limiting fails
      next();
    }
  };
}
