# Use a base image with Node.js pre-installed
FROM node:14

# Set the working directory inside the container
WORKDIR /app

# Copy package.json and package-lock.json to the working directory
COPY package*.json ./

# Install project dependencies
RUN npm install

# Copy the entire project directory into the container
COPY . .

# Build the Vue.js application
RUN npm run build

# Expose the desired port for the application
EXPOSE 8080

# Start the application when the container is launched
CMD ["npm", "run", "serve"]