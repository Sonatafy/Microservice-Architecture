FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./
RUN npm install

# Copy source code (for production build)
COPY . .

# Expose ports for both dev and prod
EXPOSE 8080 80

# Use a command that works for both dev and prod
CMD ["sh", "-c", "if [ \"$NODE_ENV\" = \"production\" ]; then npm run build && npm run serve; else npm run serve; fi"]