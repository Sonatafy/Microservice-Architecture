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
