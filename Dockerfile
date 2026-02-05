FROM ubuntu:20.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    gcc \
    g++ \
    make \
    pkg-config \
    protobuf-compiler \
    libprotobuf-dev \
    libevent-dev \
    libssl-dev \
    libunwind-dev \
    libgtest-dev \
    iputils-ping \
    netcat \
    iproute2 \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /nopaxos

# Copy source code
COPY . .

# Build NOPaxos
RUN make PARANOID=0

# Keep container running
CMD ["/bin/bash", "-c", "tail -f /dev/null"]

