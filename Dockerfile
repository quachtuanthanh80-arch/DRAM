# Dockerfile for Q-Shield Memory Controller Evaluation Environment
# Base Image: Ubuntu 22.04 LTS (x86_64)

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install base build tools and hardware verification toolchains
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    iverilog \
    verilator \
    yosys \
    z3 \
    help2man \
    perl \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /workspace

# Copy dependency requirements
COPY requirements.txt /workspace/requirements.txt

# Install Python packages and SymbiYosys
RUN pip3 install --no-cache-dir --upgrade pip && \
    pip3 install --no-cache-dir -r requirements.txt && \
    pip3 install --no-cache-dir sby

# Set default command to bash
CMD ["/bin/bash"]
