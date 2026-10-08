# Installation & Toolchain Setup Guide

This document describes how to set up the verification, simulation, and synthesis environments required to build, test, and evaluate the **Q-Shield** memory controller.

---

## 1. Supported Operating Systems

- **Ubuntu Linux 22.04 LTS (x86_64)**: Primary recommended native environment.
- **Windows 11 with WSL2 (Ubuntu 22.04)**: Fully supported for co-simulation and synthesis.
- **Windows 11 Native**: Supported for Icarus Verilog regression and Python scripts.

---

## 2. Quick Installation (Ubuntu 22.04 / WSL2)

Execute the following commands to install all core system dependencies:

```bash
# Update package repositories
sudo apt-get update && sudo apt-get install -y \
    build-essential \
    cmake \
    git \
    python3 \
    python3-pip \
    python3-venv \
    iverilog \
    verilator \
    yosys \
    z3 \
    libgoogle-perftools-dev \
    help2man \
    perl

# Create and activate Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Python verification and plotting dependencies
pip install --upgrade pip
pip install -r requirements.txt
```

---

## 3. Formal Verification Suite (SymbiYosys)

To install SymbiYosys (SBY) for hardware assertion proofs:

```bash
# Install SBY via pip
pip install sby

# Verify solver installation
sby --version
z3 --version
```

---

## 4. Hardware Simulation Suite (Verilator & Cocotb)

Verify Verilator and Cocotb installation:

```bash
# Verify Verilator version (>= 5.020 recommended)
verilator --version

# Verify Cocotb installation
python3 -c "import cocotb; print('Cocotb Version:', cocotb.__version__)"
```

---

## 5. Architectural Simulator (Ramulator 2.0)

To build Ramulator 2.0 with DDR5 extensions:

```bash
# Clone Ramulator 2.0 repository
git clone https://github.com/CMU-SAFARI/ramulator2.git
cd ramulator2

# Compile Ramulator2 binary and Python bindings
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)

# Export Python module path
export PYTHONPATH=$PYTHONPATH:$(pwd)/python
export RAMULATOR2_PATH=$(pwd)
```

---

## 6. Verification Environment Sanity Check

Run the regression self-check script to confirm complete environment readiness:

```bash
python3 run_iverilog_regression.py
```
If all 14 testbenches report `[PASS]`, the installation is complete and verified.
