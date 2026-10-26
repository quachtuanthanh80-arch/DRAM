# Dockerfile for Q-Shield Memory Controller Artifact Evaluation & Reproducibility
# Base Image: Ubuntu 24.04 LTS (x86_64) with Icarus Verilog 12.0, Verilator 5.x, Yosys & Z3

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV PYTHONUNBUFFERED=1

# Install hardware verification, simulation, and synthesis dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    iverilog \
    verilator \
    yosys \
    z3 \
    git \
    python3 \
    python-is-python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    make \
    help2man \
    perl \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /workspace

# Install Python verification dependencies (Cocotb 2.x, NumPy, Matplotlib, SciPy, Pytest)
COPY requirements.txt /workspace/requirements.txt
RUN pip3 install --no-cache-dir --break-system-packages -r requirements.txt pytest

# Copy repository source code (filtered via .dockerignore)
COPY . /workspace

# Default entrypoint reproduces all RTL regressions, attack emulations, SOTA matrices, and golden checks
CMD ["python3", "run_minimal_example.py"]
