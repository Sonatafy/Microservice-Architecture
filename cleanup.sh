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
