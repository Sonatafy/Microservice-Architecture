# Microservice Template Makefile
# This file provides shortcuts for common Docker operations

# Default environment variables
ENV ?= dev
NODE_ENV ?= development
API_PORT ?= 3001
FRONTEND_PORT ?= 8081

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
