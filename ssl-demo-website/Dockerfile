# Use nginx as the base image for serving static files
FROM nginx:alpine

# Set maintainer information
LABEL maintainer="SSL Certificate Inspector"
LABEL description="A containerized SSL certificate analysis website"

# Remove default nginx website
RUN rm -rf /usr/share/nginx/html/*

# Copy our website files to nginx html directory
COPY index.html /usr/share/nginx/html/
COPY cert-analyzer.js /usr/share/nginx/html/
COPY nginx.conf /etc/nginx/nginx.conf

# Create a health check endpoint
RUN echo '<!DOCTYPE html><html><head><title>Health Check</title></head><body><h1>OK</h1><p>SSL Certificate Inspector is running</p></body></html>' > /usr/share/nginx/html/health

# Create directory for SSL certificates (if needed for custom certs)
RUN mkdir -p /etc/nginx/ssl

# Set proper permissions
RUN chown -R nginx:nginx /usr/share/nginx/html
RUN chmod -R 755 /usr/share/nginx/html

# Expose ports
EXPOSE 80 443

# Add health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost/health || exit 1

# Start nginx
CMD ["nginx", "-g", "daemon off;"] 