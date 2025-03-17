FROM nginx:alpine

# Install required packages
RUN apk add --no-cache \
    python3 \
    py3-pip \
    python3-dev \
    openssl \
    gcc \
    musl-dev \
    libffi-dev \
    openssl-dev \
    cargo \
    rust

# Set up Python virtual environment
RUN python3 -m venv /venv
ENV PATH="/venv/bin:$PATH"

# Install Python dependencies
COPY requirements.txt /app/
RUN . /venv/bin/activate && pip install --upgrade pip && pip install -r /app/requirements.txt

# Copy website files
COPY src/ /usr/share/nginx/html/
COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY nginx/nginx.conf /etc/nginx/nginx.conf

# Create directory for SSL certificates
RUN mkdir -p /etc/nginx/ssl

# Copy SSL certificates (these will be mounted from host)
COPY certs/ /etc/nginx/ssl/

# Copy the entrypoint script
COPY entrypoint.sh /
RUN chmod +x /entrypoint.sh

# Expose ports
EXPOSE 80 443

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"] 