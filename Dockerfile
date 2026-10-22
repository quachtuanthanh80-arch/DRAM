# Dockerfile for Q-Shield Memory Controller Evaluation Environment
# Base Image: Ubuntu 22.04 LTS (x86_64)

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install base build tools and hardware verification dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    autoconf \
    gperf \
    bison \
    flex \
    libbz2-dev \
    zlib1g-dev \
    libreadline-dev \
    cmake \
    ccache \
    mold \
    git \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    yosys \
    z3 \
    help2man \
    perl \
    ca-certificates \
    curl \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install modern Verilator (v5.052)
RUN curl -fsSL https://github.com/veryl-lang/verilator-package/releases/download/v5.052/verilator-ubuntu-22.04.zip -o /tmp/verilator.zip && \
    unzip -q -o /tmp/verilator.zip -d /usr/local && \
    rm /tmp/verilator.zip

# Build and install modern Icarus Verilog (v12) from source
RUN git clone --depth 1 -b v12-branch https://github.com/steveicarus/iverilog.git /tmp/iverilog && \
    cd /tmp/iverilog && \
    sh autoconf.sh && \
    ./configure && \
    make -j$(nproc) && \
    make install && \
    rm -rf /tmp/iverilog

# Set working directory
WORKDIR /workspace

# Copy dependency requirements
COPY requirements.txt /workspace/requirements.txt

# Install Python packages and SymbiYosys
RUN pip3 install --no-cache-dir --upgrade pip && \
    pip3 install --no-cache-dir -r requirements.txt && \
    git clone https://github.com/YosysHQ/sby.git /tmp/sby && \
    make -C /tmp/sby install && \
    rm -rf /tmp/sby

# Set default command to bash
CMD ["/bin/bash"]
