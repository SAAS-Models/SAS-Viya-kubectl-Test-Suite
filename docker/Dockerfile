FROM python:3.9-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    gnupg \
    lsb-release \
    openssh-client \
    netcat-openbsd \
    jq \
    git \
    make \
    && rm -rf /var/lib/apt/lists/*

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

# Install AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws

# Set working directory
WORKDIR /app

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the entire project
COPY . .

# Make scripts executable
RUN chmod +x scripts/**/*.sh tests/**/*.sh

# Create directories for logs and reports
RUN mkdir -p logs reports

# Set environment variables
ENV PYTHONPATH=/app/lib/python:$PYTHONPATH
ENV PATH=/app/scripts/setup:/app/scripts/teardown:/app/scripts/utils:$PATH

# Default command
CMD ["make", "test"]
