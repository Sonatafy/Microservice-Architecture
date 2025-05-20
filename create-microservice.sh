#!/bin/bash
# create-microservice-template.sh
#
# This script creates a complete event-driven microservice architecture template
# based on similar patterns to the Loadsure Insurance Integration project.
#
# Usage: ./create-microservice-template.sh <project-name>

set -e  # Exit on error

# Default settings
PROJECT_NAME=${1:-""}
ROOT_DIR=$(pwd)

# Text formatting
bold=$(tput bold)
normal=$(tput sgr0)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)
red=$(tput setaf 1)

# Print banner
echo "================================================"
echo "${bold}Event-Driven Microservice Template Generator${normal}"
echo "================================================"
echo

# Check if directory is already git initialized
if [ ! -d ".git" ]; then
  echo "${yellow}Warning: Current directory does not appear to be a git repository.${normal}"
  read -p "Do you want to initialize git repository? (y/n): " init_git
  if [[ $init_git =~ ^[Yy]$ ]]; then
    git init
    echo "${green}Git repository initialized.${normal}"
  fi
fi

# Print settings
echo "${blue}Project Settings:${normal}"
echo "  Project Name: ${PROJECT_NAME}"
echo "  Root Directory: ${ROOT_DIR}"
echo

# Confirm with user
read -p "Do you want to proceed with these settings? (y/n): " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
  echo "${red}Template generation cancelled.${normal}"
  exit 1
fi

# Create directory structure
echo "Creating directory structure..."
mkdir -p backend/src/{controllers,services,middleware,utils}
mkdir -p backend/src/__tests__/{unit,integration}
mkdir -p backend/database/{migrations,models,seeders,config}
mkdir -p backend/scripts
mkdir -p backend/docs
mkdir -p frontend/src/{components,services,store,views}
mkdir -p frontend/public
mkdir -p nginx

# Generate root level files

# .gitignore
cat > .gitignore << 'EOF'
# Node.js dependencies
node_modules/
npm-debug.log
yarn-debug.log
yarn-error.log
package-lock.json
yarn.lock

# Environment variables
.env
.env.local
.env.development
.env.test
.env.production
.env.local
.env.development.local
.env.test.local
.env.production.local

# Build files
/dist
/build
/coverage
/.nyc_output
/.next
/.nuxt
/.vuepress/dist
/.serverless
/out
.webpack

# OS specific files
.DS_Store
Thumbs.db
Desktop.ini

# IDE specific files
.idea/
.vscode/
*.sublime-project
*.sublime-workspace
*.suo
*.ntvs*
*.njsproj
*.sln
*.sw?

# Docker volumes and data
/data
/docker/data
/postgres-data
/.docker
/rabbitmq_data
/pgdata

# Logs
logs
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*
lerna-debug.log*

# Backend specific
backend/node_modules/
backend/dist/
backend/data/
backend/.env
backend/coverage/

# Frontend specific
frontend/node_modules/
frontend/dist/
frontend/.env
frontend/.cache/

# Temporary files
.tmp
.temp
.cache
EOF

# .dockerignore
cat > .dockerignore << 'EOF'
node_modules
.git
.github
.vscode
.env
*.log
EOF

# Backend .dockerignore
cat > backend/.dockerignore << 'EOF'
node_modules
.git
.env
*.log
coverage
EOF

# docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  rabbitmq:
    image: rabbitmq:3.12-management
    ports:
      - "5672:5672"
      - "15672:15672"
    environment:
      - RABBITMQ_DEFAULT_USER=${RABBITMQ_USER}
      - RABBITMQ_DEFAULT_PASS=${RABBITMQ_PASS}
    volumes:
      - rabbitmq_data:/var/lib/rabbitmq
    healthcheck:
      test: ["CMD", "rabbitmqctl", "status"]
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      resources:
        limits:
          memory: 512M

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 10
    deploy:
      resources:
        limits:
          memory: 256M
    command: redis-server --appendonly yes

  postgres:
    image: postgres:14-alpine
    ports:
      - "5432:5432"
    environment:
      - POSTGRES_USER=${DB_USERNAME}
      - POSTGRES_PASSWORD=${DB_PASSWORD}
      # DB_NAME will be overridden in environment-specific files
      - POSTGRES_DB=${DB_NAME:-microservice_db}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USERNAME} -d ${DB_NAME:-microservice_db}"]
      interval: 5s
      timeout: 5s
      retries: 10
    deploy:
      resources:
        limits:
          memory: 512M

  db-setup:
    build:
      context: ./backend
      dockerfile: Dockerfile
      cache_from:
        - node:18-alpine
    environment:
      - NODE_ENV=${NODE_ENV:-development}
      - DB_DIALECT=${DB_DIALECT:-postgres}
      - DB_HOST=${DB_HOST:-postgres}
      - DB_PORT=${DB_PORT:-5432}
      - DB_USERNAME=${DB_USERNAME}
      - DB_PASSWORD=${DB_PASSWORD}
      - DB_NAME=${DB_NAME:-microservice_db}
      - DB_SSL=${DB_SSL:-false}
    depends_on:
      postgres:
        condition: service_healthy
    volumes:
      - ./backend:/usr/src/app
      - /usr/src/app/node_modules
    command: >
      sh -c "
        echo 'Running database migrations...' &&
        npx sequelize-cli db:migrate &&
        echo 'Migrations completed successfully!'
      "
    restart: "no"

  api-service:
    build:
      context: ./backend
      dockerfile: Dockerfile
    expose:
      - "3000"
    environment:
      - NODE_ENV=${NODE_ENV:-development}
      - PORT=3000
      - RABBITMQ_URL=${RABBITMQ_URL}
      - REDIS_URL=${REDIS_URL}
      - NODE_OPTIONS=--experimental-vm-modules
      - DB_SSL=${DB_SSL:-false}
      - DB_DIALECT=${DB_DIALECT:-postgres}
      - DB_HOST=${DB_HOST:-postgres}
      - DB_PORT=${DB_PORT:-5432}
      - DB_USERNAME=${DB_USERNAME}
      - DB_PASSWORD=${DB_PASSWORD}
      - DB_NAME=${DB_NAME:-microservice_db}
      - RATE_LIMIT_WINDOW_MS=60000
      - RATE_LIMIT_MAX_REQUESTS=100
      - DOCKER_SCALE=true
      - SERVICE_INSTANCE=${HOSTNAME}
    volumes:
      - ./backend:/usr/src/app
      - /usr/src/app/node_modules
    depends_on:
      db-setup:
        condition: service_completed_successfully
      rabbitmq:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3000/health"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s
    deploy:
      replicas: 2
      update_config:
        parallelism: 1
        delay: 10s
      restart_policy:
        condition: on-failure

  nginx:
    image: nginx:alpine
    ports:
      - "3000:80"  # Expose NGINX on port 3000
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/conf.d/default.conf
    depends_on:
      - api-service
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80/health"]
      interval: 10s
      timeout: 5s
      retries: 5

  worker-service:
    build:
      context: ./backend
      dockerfile: Dockerfile
    environment:
      - NODE_ENV=${NODE_ENV:-development}
      - RABBITMQ_URL=${RABBITMQ_URL}
      - REDIS_URL=${REDIS_URL}
      - NODE_OPTIONS=--experimental-vm-modules
      - DB_SSL=${DB_SSL:-false}
      - DB_DIALECT=${DB_DIALECT:-postgres}
      - DB_HOST=${DB_HOST:-postgres}
      - DB_PORT=${DB_PORT:-5432}
      - DB_USERNAME=${DB_USERNAME}
      - DB_PASSWORD=${DB_PASSWORD}
      - DB_NAME=${DB_NAME:-microservice_db}
      - WORKER_CONCURRENCY=3
      - WORKER_ID=${HOSTNAME}
    volumes:
      - ./backend:/usr/src/app
      - /usr/src/app/node_modules
    depends_on:
      api-service:
        condition: service_healthy
      redis:
        condition: service_healthy
    command: node src/services/workerService.js
    deploy:
      replicas: 2
      update_config:
        parallelism: 1
        delay: 10s
      restart_policy:
        condition: on-failure
      resources:
        limits:
          cpus: '0.5'
          memory: 512M

  queue-monitor:
    build:
      context: ./backend
      dockerfile: Dockerfile
    environment:
      - NODE_ENV=${NODE_ENV:-development}
      - RABBITMQ_URL=${RABBITMQ_URL}
      - REDIS_URL=${REDIS_URL}
      - DOCKER_SCALE=true
      - MIN_WORKERS=1
      - MAX_WORKERS=5
      - SCALE_UP_THRESHOLD=10
      - SCALE_DOWN_THRESHOLD=2
      - CHECK_INTERVAL=10000
    volumes:
      - ./backend:/usr/src/app
      - /usr/src/app/node_modules
      - /var/run/docker.sock:/var/run/docker.sock
    depends_on:
      rabbitmq:
        condition: service_healthy
      redis:
        condition: service_healthy
    command: node src/services/queueMonitorStarter.js

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
    ports:
      - "8080:8080"
    volumes:
      - ./frontend:/app
      - /app/node_modules
    environment:
      - NODE_ENV=${NODE_ENV:-development}
      - VUE_APP_API_URL=http://localhost:3000/api
    depends_on:
      - api-service
    deploy:
      replicas: 1

volumes:
  rabbitmq_data:
  postgres_data:
  redis_data:
EOF

# docker-compose.dev.yml
cat > docker-compose.dev.yml << 'EOF'
version: '3.8'

# Development environment specific settings that override the base docker-compose.yml

services:
  # Development-specific environment variables for PostgreSQL
  postgres:
    environment:
      - POSTGRES_DB=microservice_dev

  # Development-specific database setup
  db-setup:
    environment:
      - NODE_ENV=development
      - DB_NAME=microservice_dev
    command: >
      sh -c "
        echo 'Running database migrations for development...' &&
        npx sequelize-cli db:migrate &&
        echo 'Migrations completed successfully!'
      "

  # Development-specific API service settings
  api-service:
    environment:
      - NODE_ENV=development
      - DB_NAME=microservice_dev
    command: npx nodemon src/index.js
    # More verbose logging for development
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # Development-specific worker service settings
  worker-service:
    environment:
      - NODE_ENV=development
      - DB_NAME=microservice_dev
    command: npx nodemon src/services/workerService.js
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # Development-specific frontend settings
  frontend:
    environment:
      - NODE_ENV=development
    command: npm run serve
    # Enable hot reloading for frontend development
    volumes:
      - ./frontend:/app
      - /app/node_modules

  # Development-specific queue monitor settings
  queue-monitor:
    environment:
      - NODE_ENV=development
      - DB_NAME=microservice_dev

# Define development-specific volume names to separate from production data
volumes:
  rabbitmq_data:
    name: microservice_rabbitmq_data_dev
  postgres_data:
    name: microservice_postgres_data_dev
  redis_data:
    name: microservice_redis_data_dev
EOF

# Makefile
cat > Makefile << 'EOF'
# Microservice Template Makefile
# This file provides shortcuts for common Docker operations

# Default environment variables
ENV ?= dev
NODE_ENV ?= development

# Set compose files based on environment
ifeq ($(ENV),dev)
	COMPOSE_FILES := -f docker-compose.yml -f docker-compose.dev.yml
	NODE_ENV := development
	export DB_NAME=microservice_dev
else ifeq ($(ENV),prod)
	COMPOSE_FILES := -f docker-compose.yml
	NODE_ENV := production
	export DB_NAME=microservice
else
	COMPOSE_FILES := -f docker-compose.yml
endif

# Container organization
PROJECT_NAME := microservice-template

# Export environment variables
export NODE_ENV
export DB_NAME

# Default target
.PHONY: help
help:
	@echo "Microservice Template Commands:"
	@echo ""
	@echo "Environment Management:"
	@echo "  make up              # Start all services (default: dev environment)"
	@echo "  make up ENV=prod     # Start all services in production mode"
	@echo "  make down            # Stop all services"
	@echo "  make restart         # Restart all services"
	@echo ""
	@echo "Development Shortcuts:"
	@echo "  make dev             # Start development environment"
	@echo "  make prod            # Start production environment"
	@echo "  make rebuild-changed # Rebuild and restart only services with changed files"
	@echo ""
	@echo "Container Management:"
	@echo "  make build           # Build all containers"
	@echo "  make build-parallel  # Build all containers in parallel"
	@echo "  make pull            # Pull latest images"
	@echo "  make clean           # Remove node_modules directories and temporary files"
	@echo "  make clean-all       # Remove all containers, networks, volumes, and node_modules"
	@echo ""
	@echo "Service-specific Commands:"
	@echo "  make frontend        # Build and start only the frontend"
	@echo "  make backend         # Build and start only the backend services"
	@echo "  make db              # Start only the database"
	@echo "  make migrate         # Run database migrations"
	@echo ""
	@echo "Logs:"
	@echo "  make logs            # View logs from all services"
	@echo "  make logs-api        # View logs from API service"
	@echo "  make logs-frontend   # View logs from frontend"
	@echo ""
	@echo "Utilities:"
	@echo "  make status          # Show status of all containers"
	@echo "  make ps              # Alias for status"
	@echo "  make prune           # Remove unused Docker resources"
	@echo ""
	@echo "Current Environment: $(ENV) (DB: $(DB_NAME), NODE_ENV: $(NODE_ENV))"

# Environment shortcuts
.PHONY: dev prod
dev:
	@echo "Starting development environment..."
	@$(MAKE) ENV=dev up

prod:
	@echo "Starting production environment..."
	@$(MAKE) ENV=prod up

# Core Docker commands
.PHONY: up down restart build build-parallel pull
up:
	@echo "Starting services with $(COMPOSE_FILES)..."
	docker-compose $(COMPOSE_FILES) up -d

down:
	@echo "Stopping services..."
	docker-compose $(COMPOSE_FILES) down

restart:
	@echo "Restarting services..."
	docker-compose $(COMPOSE_FILES) restart

build:
	@echo "Building containers..."
	docker-compose $(COMPOSE_FILES) build

build-parallel:
	@echo "Building containers in parallel..."
	docker-compose $(COMPOSE_FILES) build --parallel

pull:
	@echo "Pulling latest images..."
	docker-compose $(COMPOSE_FILES) pull

# Service-specific commands
.PHONY: frontend backend db migrate
frontend:
	@echo "Starting frontend service..."
	docker-compose $(COMPOSE_FILES) up -d --build frontend

backend:
	@echo "Starting backend services..."
	docker-compose $(COMPOSE_FILES) up -d --build api-service worker-service

db:
	@echo "Starting database services..."
	docker-compose $(COMPOSE_FILES) up -d postgres rabbitmq
	@echo "Waiting for database to be ready..."
	@sleep 5
	docker-compose $(COMPOSE_FILES) up db-setup

migrate:
	@echo "Running database migrations..."
	docker-compose $(COMPOSE_FILES) run --rm db-setup

# Intelligent rebuild - detects which services need rebuilding based on changed files
.PHONY: rebuild-changed
rebuild-changed:
	@echo "Checking for changed files..."
	@if [ -n "$$(git diff --name-only HEAD | grep -E '^frontend/')" ]; then \
		echo "Frontend changes detected. Rebuilding frontend..."; \
		docker-compose $(COMPOSE_FILES) up -d --build frontend; \
	fi
	@if [ -n "$$(git diff --name-only HEAD | grep -E '^backend/')" ]; then \
		echo "Backend changes detected. Rebuilding backend services..."; \
		docker-compose $(COMPOSE_FILES) up -d --build --no-deps api-service worker-service; \
	fi
	@if [ -n "$$(git diff --name-only HEAD | grep -E '^backend/database/migrations/')" ]; then \
		echo "Migration changes detected. Running migrations..."; \
		docker-compose $(COMPOSE_FILES) run --rm db-setup npx sequelize-cli db:migrate; \
	fi
	@if [ -n "$$(git diff --name-only HEAD | grep -E 'docker-compose|Dockerfile|nginx')" ]; then \
		echo "Docker configuration changes detected. Rebuilding all services..."; \
		docker-compose $(COMPOSE_FILES) up -d --build; \
	fi
	@if [ -z "$$(git diff --name-only HEAD | grep -E '^frontend/|^backend/|docker-compose|Dockerfile|nginx')" ]; then \
		echo "No relevant changes detected."; \
	fi

# Log commands
.PHONY: logs logs-api logs-frontend
logs:
	docker-compose $(COMPOSE_FILES) logs -f

logs-api:
	docker-compose $(COMPOSE_FILES) logs -f api-service

logs-frontend:
	docker-compose $(COMPOSE_FILES) logs -f frontend

# Cleanup commands
.PHONY: clean clean-all
clean:
	@echo "Cleaning node_modules folders and temporary files..."
	@if [ -f "cleanup.sh" ]; then \
		sh cleanup.sh; \
	else \
		rm -rf node_modules; \
		rm -rf frontend/node_modules; \
		rm -rf backend/node_modules; \
	fi
	@echo "Removing temporary files..."
	@find . -name "*.log" -type f -delete
	@find . -name ".DS_Store" -type f -delete
	@find . -name "*.tmp" -type f -delete
	@echo "Cleanup complete!"

clean-all:
	@echo "Stopping all containers..."
	docker-compose $(COMPOSE_FILES) down -v
	@echo "Removing volumes..."
	docker volume prune -f
	@echo "Removing node_modules and temporary files..."
	@$(MAKE) clean
	@echo "Pruning unused Docker resources..."
	docker system prune -f
	@echo "Deep clean complete!"

# Utility commands
.PHONY: status ps prune
status:
	docker-compose $(COMPOSE_FILES) ps

ps: status

prune:
	@echo "Removing unused Docker resources..."
	docker system prune -f

# Test commands
.PHONY: test-setup test test-cleanup

test-setup:
	@echo "Setting up test environment..."
	npm install node-fetch uuid

test:
	@echo "Running tests..."
	cd backend && npm test

test-cleanup:
	@echo "Cleaning up test artifacts..."
	rm -rf node_modules

up-and-test:
	@echo "Starting services and running tests..."
	$(MAKE) up
	$(MAKE) test
EOF

# Nginx configuration
mkdir -p nginx
cat > nginx/nginx.conf << 'EOF'
server {
    listen 80;
    server_name localhost;

    # Access log configuration
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    # Increase timeouts for longer API requests
    proxy_connect_timeout 300s;
    proxy_read_timeout 300s;
    proxy_send_timeout 300s;

    # Health check endpoint
    location /health {
        access_log off;
        add_header Content-Type application/json;
        return 200 '{"status":"ok","service":"nginx","timestamp":"$time_iso8601"}';
    }

    # API traffic to API service
    location /api/ {
        # Using a resolver ensures the hostname is resolved at runtime
        resolver 127.0.0.11 valid=30s;
        set $upstream_api api-service:3000;
        
        proxy_pass http://$upstream_api;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        
        # Add a unique request ID
        proxy_set_header X-Request-ID $request_id;
        
        # Enable keep-alive (important for performance)
        proxy_set_header Connection "";
    }

    # Swagger documentation
    location /api-docs {
        resolver 127.0.0.11 valid=30s;
        set $upstream_api api-service:3000;
        
        proxy_pass http://$upstream_api/api-docs;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    # Serve frontend for root and other paths
    location / {
        resolver 127.0.0.11 valid=30s;
        set $upstream_frontend frontend:8080;
        
        proxy_pass http://$upstream_frontend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    # Error handling
    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }
}
EOF

# Create cleanup.sh
cat > cleanup.sh << 'EOF'
#!/bin/bash
# cleanup.sh

echo "Cleaning node_modules folders..."

# Clean root node_modules (if any)
if [ -d "node_modules" ]; then
  echo "Removing root node_modules"
  rm -rf node_modules
fi

# Clean backend node_modules
if [ -d "backend/node_modules" ]; then
  echo "Removing backend node_modules"
  rm -rf backend/node_modules
fi

# Clean frontend node_modules
if [ -d "frontend/node_modules" ]; then
  echo "Removing frontend node_modules"
  rm -rf frontend/node_modules
fi

echo "All node_modules folders have been removed!"
echo "To reinstall dependencies, run:"
echo "  - 'npm install' in the root directory for project tools"
echo "  - 'cd backend && npm install' for backend dependencies"
echo "  - 'cd frontend && npm install' for frontend dependencies"
EOF
chmod +x cleanup.sh

# Create run-e2e-test.sh script
cat > run-e2e-test.sh << 'EOF'
#!/bin/bash
# run-e2e-test.sh
# Script to wait for services to be ready and then run the E2E test

set -e  # Exit on error

# Configuration
API_URL=${API_URL:-"http://localhost:3000/api"}
MAX_RETRIES=30
RETRY_INTERVAL=5
HEALTH_ENDPOINT="http://localhost:3000/health"

# Print banner
echo "================================================"
echo "Microservice E2E Test Runner"
echo "================================================"
echo "API URL: $API_URL"
echo

# Ensure we have the necessary dependencies
if ! command -v node &> /dev/null; then
    echo "Error: Node.js is required but not installed."
    exit 1
fi

if ! command -v npm &> /dev/null; then
    echo "Error: npm is required but not installed."
    exit 1
fi

if ! command -v curl &> /dev/null; then
    echo "Error: curl is required but not installed."
    exit 1
fi

# Function to check if services are ready
check_services() {
    echo "Checking if services are ready..."
    
    for i in $(seq 1 $MAX_RETRIES); do
        echo "Attempt $i/$MAX_RETRIES: Checking health endpoint..."
        
        if curl -s "$HEALTH_ENDPOINT" | grep -q "\"status\":\"ok\""; then
            echo "✅ Services are ready!"
            return 0
        else
            echo "Services not ready yet. Waiting $RETRY_INTERVAL seconds..."
            sleep $RETRY_INTERVAL
        fi
    done
    
    echo "❌ Services failed to become ready within the timeout period."
    return 1
}

# Function to run the tests
run_tests() {
    echo
    echo "Starting tests..."
    echo
    
    # Export the API URL for the test script
    export API_URL
    
    # Run the test script
    cd backend && npm test
    
    # Capture exit code
    local result=$?
    
    if [ $result -eq 0 ]; then
        echo
        echo "🎉 Tests completed successfully!"
        echo
    else
        echo
        echo "❌ Tests failed with exit code: $result"
        echo
    fi
    
    return $result
}

# Main execution flow
main() {
    # 1. Wait for services to be ready
    check_services
    
    if [ $? -ne 0 ]; then
        echo "Aborting tests due to service unavailability."
        exit 1
    fi
    
    # 2. Run the tests
    run_tests
    
    # Return the result of the tests
    exit $?
}

# Run the main function
main
EOF
chmod +x run-e2e-test.sh

# Root package.json
cat > package.json << EOF
{
  "name": "${PROJECT_NAME}",
  "version": "1.0.0",
  "description": "Event-driven microservice architecture template",
  "private": true,
  "scripts": {
    "start": "docker-compose up",
    "stop": "docker-compose down",
    "dev": "docker-compose up -d",
    "logs": "docker-compose logs -f",
    "clean": "npm run clean:backend && npm run clean:frontend",
    "clean:backend": "cd backend && rm -rf node_modules",
    "clean:frontend": "cd frontend && rm -rf node_modules",
    "prepare": "husky install"
  },
  "engines": {
    "node": ">=18.0.0"
  },
  "lint-staged": {
    "backend/**/*.js": [
      "cd backend && npm run lint:fix"
    ],
    "frontend/**/*.{js,vue}": [
      "cd frontend && npm run lint:fix"
    ]
  },
  "devDependencies": {
    "husky": "^8.0.3",
    "lint-staged": "^15.2.0"
  },
  "dependencies": {
    "node-fetch": "^2.7.0",
    "uuid": "^11.1.0"
  }
}
EOF

# .sequelizerc
cat > .sequelizerc << 'EOF'
const path = require('path');

module.exports = {
  'config': path.resolve('backend/database/config/config.cjs'),
  'models-path': path.resolve('backend/database/models'),
  'seeders-path': path.resolve('backend/database/seeders'),
  'migrations-path': path.resolve('backend/database/migrations')
};
EOF

# Backend .sequelizerc
cat > backend/.sequelizerc << 'EOF'
// backend/.sequelizerc
const path = require('path');

module.exports = {
  'config': path.resolve('database/config/config.cjs'),
  'models-path': path.resolve('database/models'),
  'seeders-path': path.resolve('database/seeders'),
  'migrations-path': path.resolve('database/migrations')
};
EOF

# Create the Backend files
# Backend package.json
cat > backend/package.json << EOF
{
  "name": "${PROJECT_NAME}-backend",
  "version": "1.0.0",
  "description": "Backend services for event-driven microservice architecture",
  "main": "src/index.js",
  "scripts": {
    "start": "node src/index.js",
    "dev": "nodemon src/index.js",
    "service": "node src/services/workerService.js",
    "monitor": "node src/services/queueMonitorStarter.js",
    "test": "jest --config=jest.config.cjs",
    "test:watch": "jest --watch",
    "test:coverage": "jest --coverage",
    "test:unit": "jest src/__tests__/unit",
    "test:integration": "jest src/__tests__/integration",
    "migrate": "node scripts/run-migrations.js",
    "migrate:check": "node scripts/check-migrations.cjs",
    "migrate:status": "npx sequelize-cli db:migrate:status",
    "migrate:undo": "npx sequelize-cli db:migrate:undo",
    "seed": "npx sequelize-cli db:seed:all",
    "seed:undo": "npx sequelize-cli db:seed:undo:all",
    "lint": "eslint src/**/*.js",
    "lint:fix": "eslint src/**/*.js --fix",
    "clean": "rm -rf node_modules",
    "generate-docs": "node src/swagger.js"
  },
  "dependencies": {
    "amqplib": "^0.10.3",
    "cors": "^2.8.5",
    "dotenv": "^16.3.1",
    "express": "^4.18.2",
    "ioredis": "^5.3.2",
    "node-cache": "^5.1.2",
    "node-fetch": "^3.3.2",
    "node-schedule": "^2.1.1",
    "pg": "^8.11.3",
    "pg-hstore": "^2.3.4",
    "sequelize": "^6.35.1",
    "sequelize-cli": "^6.6.2",
    "swagger-jsdoc": "^6.2.8",
    "swagger-ui-express": "^5.0.1",
    "uuid": "^9.0.1"
  },
  "devDependencies": {
    "@babel/core": "^7.27.1",
    "@babel/plugin-syntax-dynamic-import": "^7.8.3",
    "@babel/plugin-syntax-import-meta": "^7.10.4",
    "@babel/plugin-transform-modules-commonjs": "^7.27.0",
    "@babel/preset-env": "^7.27.1",
    "babel-jest": "^29.7.0",
    "eslint": "^8.57.1",
    "jest": "^29.7.0",
    "nodemon": "^3.0.1",
    "supertest": "^6.3.4"
  },
  "type": "module",
  "engines": {
    "node": ">=18.0.0"
  }
}
EOF

# Backend Dockerfile
cat > backend/Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /usr/src/app

# Copy package files
COPY package*.json ./

# Install nodemon globally first
RUN npm install -g nodemon

# Then install all dependencies
RUN npm install

# Create data directory
RUN mkdir -p /usr/src/app/data && chmod 777 /usr/src/app/data

# Copy all source files
COPY src/ ./src/
COPY database/ ./database/
COPY scripts/ ./scripts/
COPY .env.example ./.env.example

# Expose API port
EXPOSE 3000

# Default command - can be overridden in docker-compose
CMD ["node", "src/index.js"]
EOF

# Backend .env.example
cat > backend/.env.example << 'EOF'
# Server Configuration
PORT=3000

# RabbitMQ Configuration
RABBITMQ_URL=amqp://guest:guest@rabbitmq:5672
RABBITMQ_USER=guest
RABBITMQ_PASSWORD=guest

# Custom API Configuration
API_KEY=your_custom_api_key_here
API_BASE_URL=https://example.com/api

# Database Configuration
DB_DIALECT=postgres
DB_HOST=postgres
DB_PORT=5432
DB_USERNAME=microservice
DB_PASSWORD=microservice_password
DB_NAME=microservice_db
DB_SSL=false
DB_SSL_REJECT_UNAUTHORIZED=true

# Redis Configuration
REDIS_URL=redis://redis:6379

# Timeouts (milliseconds)
REQUEST_TIMEOUT=30000
API_CALL_TIMEOUT=15000

# Node Environment
NODE_ENV=development

# Logging
LOG_LEVEL=info

# Docker Configuration
COMPOSE_DOCKER_CLI_BUILD=1
DOCKER_BUILDKIT=1

# Rate Limiting
RATE_LIMIT_WINDOW_MS=60000
RATE_LIMIT_MAX_REQUESTS=100

# Queue Scaling
MIN_WORKERS=1
MAX_WORKERS=5
SCALE_UP_THRESHOLD=10
SCALE_DOWN_THRESHOLD=2
CHECK_INTERVAL=10000
WORKER_CONCURRENCY=3
EOF

# Backend database configuration
mkdir -p backend/database/config
cat > backend/database/config/config.cjs << 'EOF'
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
EOF

# Example database migration
cat > backend/database/migrations/20250101000001-create-initial-schema.cjs << 'EOF'
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
EOF

# Create basic database models
cat > backend/database/models/Message.js << 'EOF'
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
EOF

cat > backend/database/models/Task.js << 'EOF'
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
EOF

# Create basic database index
cat > backend/database/index.js << 'EOF'
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
EOF

# Create basic database config module
cat > backend/database/config.js << 'EOF'
// ESM-compatible Sequelize config
import dotenv from 'dotenv';
import { fileURLToPath } from 'url';
import path from 'path';

// Load environment variables
dotenv.config();

// Get current environment
const env = process.env.NODE_ENV || 'development';

// Common configuration options
const baseConfig = {
  dialect: process.env.DB_DIALECT || 'postgres',
  host: process.env.DB_HOST || 'postgres',
  port: parseInt(process.env.DB_PORT || '5432', 10),
  username: process.env.DB_USERNAME,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME || 'microservice_db',
  migrationStorageTableName: 'sequelize_migrations',
  seederStorageTableName: 'sequelize_seeders',
  seederStorage: 'sequelize',
};

// Environment-specific configurations
const config = {
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

// Export the current environment's config and all configs
export default config[env];
export const configs = config;
EOF

# Create middleware, controller and service folders with sample files
mkdir -p backend/src/middleware

# Rate limiter middleware
cat > backend/src/middleware/rateLimiter.js << 'EOF'
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
EOF

# Create sample controller
mkdir -p backend/src/controllers
cat > backend/src/controllers/tasksController.js << 'EOF'
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
EOF

# Create sample service
mkdir -p backend/src/services
cat > backend/src/services/queueMonitorService.js << 'EOF'
// backend/src/services/queueMonitorService.js
import * as amqp from 'amqplib';
import { exec } from 'child_process';
import { promisify } from 'util';
import config from '../config.js';

const execPromise = promisify(exec);

/**
 * Service for monitoring queue depths and auto-scaling worker processes
 */
class QueueMonitorService {
  constructor(options = {}) {
    this.rabbitMqUrl = options.rabbitMqUrl || config.RABBITMQ_URL;
    this.queues = options.queues || [
      config.QUEUE_TASK_CREATED,
      config.QUEUE_TASK_COMPLETED
    ];
    this.checkInterval = options.checkInterval || 10000; // Default: check every 10 seconds
    this.scaleUpThreshold = options.scaleUpThreshold || 10; // Scale up when queue depth reaches this value
    this.scaleDownThreshold = options.scaleDownThreshold || 2; // Scale down when queue depth falls below this value
    this.maxWorkers = options.maxWorkers || 5; // Maximum number of worker processes
    this.minWorkers = options.minWorkers || 1; // Minimum number of worker processes
    this.isRunning = false;
    this.checkTimer = null;
    this.connection = null;
    this.channel = null;
    this.dockerMode = process.env.DOCKER_SCALE === 'true';
    this.currentWorkerCount = this.minWorkers; // Start with minimum workers
  }

  /**
   * Start the queue monitor service
   */
  async start() {
    if (this.isRunning) {
      console.log('Queue monitor service is already running');
      return;
    }

    try {
      console.log('Starting queue monitor service...');
      console.log(`Docker mode: ${this.dockerMode ? 'enabled' : 'disabled'}`);
      
      // Connect to RabbitMQ
      this.connection = await amqp.connect(this.rabbitMqUrl);
      this.channel = await this.connection.createChannel();
      
      // Set up monitoring interval
      this.checkTimer = setInterval(() => this.checkQueueDepths(), this.checkInterval);
      this.isRunning = true;
      
      // Start minimum number of workers
      await this.ensureMinimumWorkers();
      
      // Handle connection close
      this.connection.on('close', async (err) => {
        console.error('Queue monitor: RabbitMQ connection closed', err);
        clearInterval(this.checkTimer);
        this.isRunning = false;
        
        // Attempt to reconnect
        console.log('Queue monitor: Attempting to reconnect in 5 seconds...');
        setTimeout(() => this.start(), 5000);
      });
      
      console.log('Queue monitor service started successfully');
    } catch (error) {
      console.error('Error starting queue monitor service:', error);
      
      // Clean up if error during startup
      if (this.connection) {
        try {
          await this.connection.close();
        } catch (closeError) {
          console.error('Error closing connection:', closeError);
        }
      }
      
      this.isRunning = false;
      
      // Attempt to restart
      console.log('Queue monitor: Attempting to restart in 5 seconds...');
      setTimeout(() => this.start(), 5000);
    }
  }

  /**
   * Stop the queue monitor service
   */
  async stop() {
    if (!this.isRunning) {
      console.log('Queue monitor service is not running');
      return;
    }

    console.log('Stopping queue monitor service...');
    
    clearInterval(this.checkTimer);
    this.checkTimer = null;
    
    try {
      if (this.connection) {
        await this.connection.close();
      }
    } catch (error) {
      console.error('Error closing connection:', error);
    }
    
    this.isRunning = false;
    console.log('Queue monitor service stopped');
  }

  /**
   * Check the depth of all monitored queues
   */
  async checkQueueDepths() {
    if (!this.isRunning || !this.channel) return;
    
    try {
      let totalMessages = 0;
      
      // Check each queue and sum the total messages
      for (const queueName of this.queues) {
        const queueInfo = await this.channel.assertQueue(queueName, { durable: true });
        const messageCount = queueInfo.messageCount;
        totalMessages += messageCount;
        
        console.log(`Queue ${queueName}: ${messageCount} messages`);
      }
      
      console.log(`Total messages across all queues: ${totalMessages}`);
      
      // Determine if scaling is needed
      if (totalMessages > this.scaleUpThreshold && this.currentWorkerCount < this.maxWorkers) {
        // Scale up: add more workers
        await this.scaleUp(Math.min(
          this.maxWorkers - this.currentWorkerCount,
          Math.ceil(totalMessages / this.scaleUpThreshold)
        ));
      } else if (totalMessages < this.scaleDownThreshold && this.currentWorkerCount > this.minWorkers) {
        // Scale down: remove excess workers
        await this.scaleDown(Math.min(
          this.currentWorkerCount - this.minWorkers,
          Math.ceil((this.scaleDownThreshold - totalMessages) / this.scaleDownThreshold)
        ));
      }
    } catch (error) {
      console.error('Error checking queue depths:', error);
    }
  }

  /**
   * Ensure the minimum number of workers are running
   */
  async ensureMinimumWorkers() {
    try {
      if (this.dockerMode) {
        // For Docker, check current scale
        const { stdout } = await execPromise('docker-compose ps -q worker-service | wc -l');
        const currentWorkers = parseInt(stdout.trim(), 10);
        this.currentWorkerCount = currentWorkers;
        
        if (currentWorkers < this.minWorkers) {
          await this.scaleUp(this.minWorkers - currentWorkers);
        }
      } else {
        // In non-Docker mode, scale to minimum directly
        if (this.currentWorkerCount < this.minWorkers) {
          await this.scaleUp(this.minWorkers - this.currentWorkerCount);
        }
      }
    } catch (error) {
      console.error('Error ensuring minimum workers:', error);
    }
  }

  /**
   * Scale up by starting new worker processes
   * @param {number} count - Number of workers to add
   */
  async scaleUp(count) {
    console.log(`Scaling up: adding ${count} workers`);
    
    try {
      if (this.dockerMode) {
        // For Docker environments, use docker-compose scale
        const targetWorkers = this.currentWorkerCount + count;
        console.log(`Scaling worker-service to ${targetWorkers} workers via Docker`);
        
        // Using docker-compose with deploy mode needs service update
        const { stdout, stderr } = await execPromise(
          `docker-compose up -d --scale worker-service=${targetWorkers}`
        );
        
        console.log('Scale up output:', stdout);
        if (stderr) {
          console.error('Scale up error:', stderr);
        }
        
        this.currentWorkerCount = targetWorkers;
        console.log(`New worker count: ${this.currentWorkerCount}`);
      } else {
        console.log('Non-Docker scaling not implemented in this version');
        // For local environment, we would spawn new processes here
        this.currentWorkerCount += count;
      }
    } catch (error) {
      console.error('Error scaling up workers:', error);
    }
  }

  /**
   * Scale down by stopping excess worker processes
   * @param {number} count - Number of workers to remove
   */
  async scaleDown(count) {
    if (this.currentWorkerCount <= this.minWorkers) return;
    
    const actualCount = Math.min(count, this.currentWorkerCount - this.minWorkers);
    console.log(`Scaling down: removing ${actualCount} workers`);
    
    try {
      if (this.dockerMode) {
        // For Docker environments, use docker-compose scale
        const targetWorkers = this.currentWorkerCount - actualCount;
        console.log(`Scaling worker-service to ${targetWorkers} workers via Docker`);
        
        const { stdout, stderr } = await execPromise(
          `docker-compose up -d --scale worker-service=${targetWorkers}`
        );
        
        console.log('Scale down output:', stdout);
        if (stderr) {
          console.error('Scale down error:', stderr);
        }
        
        this.currentWorkerCount = targetWorkers;
        console.log(`New worker count: ${this.currentWorkerCount}`);
      } else {
        console.log('Non-Docker scaling not implemented in this version');
        // For local environment, we would stop processes here
        this.currentWorkerCount -= actualCount;
      }
    } catch (error) {
      console.error('Error scaling down workers:', error);
    }
  }
}

export default QueueMonitorService;
EOF

# backend/src/index.js (API Service)
cat > backend/src/index.js << 'EOF'
import express from 'express';
import cors from 'cors';
import { v4 as uuidv4 } from 'uuid';
import * as amqp from 'amqplib';
import Redis from 'ioredis';
import config from './config.js';

// Create Express app
const app = express();
app.use(cors());
app.use(express.json());

// Add request ID middleware
app.use((req, res, next) => {
  req.id = req.headers['x-request-id'] || uuidv4();
  res.setHeader('X-Request-ID', req.id);
  next();
});

// Add basic logging middleware
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = Date.now() - start;
    console.log(`${req.method} ${req.originalUrl} ${res.statusCode} ${duration}ms [${req.id}]`);
  });
  next();
});

// Create Redis client
const redis = new Redis(config.REDIS_URL || 'redis://redis:6379', {
  keyPrefix: 'api:',
  maxRetriesPerRequest: 3,
  connectTimeout: 5000
});

// Connect to RabbitMQ
let channel;
async function setupRabbitMQ() {
  try {
    console.log('Connecting to RabbitMQ...');
    const connection = await amqp.connect(config.RABBITMQ_URL);
    
    // Create a channel
    channel = await connection.createChannel();
    
    // Ensure queues exist
    await channel.assertQueue(config.QUEUE_TASK_CREATED, { durable: true });
    await channel.assertQueue(config.QUEUE_TASK_COMPLETED, { durable: true });
    
    console.log('RabbitMQ connection established');
    return channel;
  } catch (error) {
    console.error('Error connecting to RabbitMQ:', error);
    console.log('Attempting to reconnect in 5 seconds...');
    setTimeout(setupRabbitMQ, 5000);
  }
}

// API endpoints
app.post('/api/tasks', async (req, res) => {
  try {
    const taskId = uuidv4();
    const task = {
      taskId,
      type: req.body.type || 'default_task',
      data: req.body.data || {},
      status: 'pending',
      createdAt: new Date().toISOString()
    };
    
    // Store the task in Redis for tracking
    await redis.set(`task:${taskId}`, JSON.stringify(task), 'EX', 3600);
    
    // Publish task to RabbitMQ
    await channel.sendToQueue(
      config.QUEUE_TASK_CREATED,
      Buffer.from(JSON.stringify(task)),
      { persistent: true }
    );
    
    res.status(201).json({
      status: 'success',
      taskId,
      message: 'Task created and queued for processing'
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

app.get('/api/tasks/:id', async (req, res) => {
  try {
    const taskId = req.params.id;
    const taskJson = await redis.get(`task:${taskId}`);
    
    if (!taskJson) {
      return res.status(404).json({
        status: 'error',
        error: 'Task not found'
      });
    }
    
    const task = JSON.parse(taskJson);
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

// Health check endpoint
app.get('/health', async (req, res) => {
  // Check Redis connection
  let redisStatus = 'disconnected';
  try {
    const pingResult = await redis.ping();
    redisStatus = pingResult === 'PONG' ? 'connected' : 'error';
  } catch (redisError) {
    redisStatus = 'error';
  }
  
  // Check RabbitMQ status
  const rabbitmqStatus = channel ? 'connected' : 'disconnected';
  
  res.json({ 
    status: redisStatus === 'connected' && rabbitmqStatus === 'connected' ? 'ok' : 'degraded', 
    timestamp: new Date().toISOString(),
    instanceId: process.env.HOSTNAME || 'unknown'
  });
});

// Start the server
async function startServer() {
  try {
    // Connect to RabbitMQ
    await setupRabbitMQ();
    
    // Start the API server
    app.listen(config.PORT, () => {
      console.log(`API Service running on port ${config.PORT}`);
      console.log(`Instance ID: ${process.env.HOSTNAME || 'unknown'}`);
    });
  } catch (error) {
    console.error('Failed to start services:', error);
    process.exit(1);
  }
}

// Start the server
startServer();

// Error handling
process.on('uncaughtException', (error) => {
  console.error('Uncaught Exception:', error);
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
});

export { app, redis };
EOF

# backend/src/services/workerService.js
cat > backend/src/services/workerService.js << 'EOF'
import * as amqp from 'amqplib';
import Redis from 'ioredis';
import config from '../config.js';

// Worker configuration
const WORKER_CONCURRENCY = parseInt(process.env.WORKER_CONCURRENCY || '3', 10);
const WORKER_ID = process.env.WORKER_ID || `worker-${process.pid}`;

// Track active jobs
let activeJobs = 0;

// Initialize Redis client
const redis = new Redis(config.REDIS_URL || 'redis://redis:6379', {
  keyPrefix: 'worker:',
  maxRetriesPerRequest: 3,
  connectTimeout: 5000
});

/**
 * Start the worker service
 */
async function startWorkerService() {
  try {
    console.log(`Worker Service [${WORKER_ID}]: Starting with concurrency ${WORKER_CONCURRENCY}`);
    
    // Connect to RabbitMQ
    const connection = await amqp.connect(config.RABBITMQ_URL);
    const channel = await connection.createChannel();

    // Set prefetch based on concurrency
    channel.prefetch(WORKER_CONCURRENCY);
    
    // Ensure queues exist
    await channel.assertQueue(config.QUEUE_TASK_CREATED, { durable: true });
    await channel.assertQueue(config.QUEUE_TASK_COMPLETED, { durable: true });
    
    // Process messages from task-created queue
    await channel.consume(config.QUEUE_TASK_CREATED, async (msg) => {
      if (msg !== null) {
        activeJobs++;
        const startTime = Date.now();
        
        try {
          const data = JSON.parse(msg.content.toString());
          const taskId = data.taskId;
          
          console.log(`Processing task: ${taskId}`);
          
          // Check if this task is already being processed
          const processingKey = `processing:${taskId}`;
          const isBeingProcessed = await redis.exists(processingKey);
          
          if (isBeingProcessed) {
            console.log(`Task ${taskId} is already being processed - skipping`);
            channel.ack(msg);
            activeJobs--;
            return;
          }
          
          // Mark this task as being processed
          await redis.set(processingKey, WORKER_ID, 'EX', 60);
          
          // Update task status in Redis
          const taskJson = await redis.get(`task:${taskId}`);
          if (taskJson) {
            const task = JSON.parse(taskJson);
            task.status = 'processing';
            task.assignedTo = WORKER_ID;
            task.processingStartedAt = new Date().toISOString();
            await redis.set(`task:${taskId}`, JSON.stringify(task), 'EX', 3600);
          }
          
          // Process the task (example implementation)
          const result = await processTask(data);
          
          // Update task with result
          if (taskJson) {
            const task = JSON.parse(taskJson);
            task.status = 'completed';
            task.result = result;
            task.completedAt = new Date().toISOString();
            await redis.set(`task:${taskId}`, JSON.stringify(task), 'EX', 3600);
          }
          
          // Publish completion event
          await channel.sendToQueue(
            config.QUEUE_TASK_COMPLETED,
            Buffer.from(JSON.stringify({
              taskId,
              result,
              workerId: WORKER_ID,
              timestamp: new Date().toISOString()
            })),
            { persistent: true }
          );
          
          // Acknowledge the message
          channel.ack(msg);
          
          // Clean up Redis processing marker
          await redis.del(processingKey);
          
          console.log(`Task ${taskId} completed successfully`);
        } catch (error) {
          console.error(`Error processing message:`, error);
          
          // Either retry or acknowledge the message
          channel.nack(msg, false, true); // Requeue the message
        } finally {
          activeJobs--;
          const processingTime = Date.now() - startTime;
          console.log(`Processing took ${processingTime}ms, active jobs: ${activeJobs}`);
        }
      }
    });
    
    console.log(`Worker Service [${WORKER_ID}] started and ready to process tasks`);
    return { connection, channel };
  } catch (error) {
    console.error('Worker Service: Error starting service:', error);
    console.log('Attempting to restart in 5 seconds...');
    setTimeout(startWorkerService, 5000);
    return null;
  }
}

/**
 * Process a task (example implementation)
 * @param {Object} task - Task data
 * @returns {Promise<Object>} Processing result
 */
async function processTask(task) {
  // For demonstration - simulate processing time
  await new Promise(resolve => setTimeout(resolve, 2000));
  
  // Handle different task types
  switch (task.type) {
    case 'example_task':
      return {
        processed: true,
        message: `Task ${task.taskId} processed successfully`,
        timestamp: new Date().toISOString()
      };
    default:
      return {
        processed: true,
        message: `Processed task of type ${task.type}`,
        timestamp: new Date().toISOString()
      };
  }
}

// Handle shutdown gracefully
async function gracefulShutdown(connection) {
  console.log(`Worker Service [${WORKER_ID}]: Shutting down...`);
  
  // Wait for active jobs to complete (up to 10 seconds)
  const maxWaitTime = 10000;
  const startTime = Date.now();
  
  while (activeJobs > 0 && (Date.now() - startTime) < maxWaitTime) {
    console.log(`Waiting for ${activeJobs} active jobs to complete...`);
    await new Promise(resolve => setTimeout(resolve, 500));
  }
  
  // Close connections
  try {
    await connection.close();
    await redis.quit();
  } catch (error) {
    console.error('Error during shutdown:', error);
  }
  
  console.log('Worker service shutdown complete');
}

// Start the worker service
const workerPromise = startWorkerService();

// Handle termination signals
process.on('SIGTERM', async () => {
  console.log('SIGTERM received, shutting down worker...');
  const { connection } = await workerPromise;
  await gracefulShutdown(connection);
  process.exit(0);
});

process.on('SIGINT', async () => {
  console.log('SIGINT received, shutting down worker...');
  const { connection } = await workerPromise;
  await gracefulShutdown(connection);
  process.exit(0);
});
EOF

# backend/src/config.js
cat > backend/src/config.js << 'EOF'
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
EOF