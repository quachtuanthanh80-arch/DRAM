# File: cocotb2_compat.py
# Chức năng: Lớp tương thích ngược monkey-patch các API cũ của cocotb 1.x giúp cocotbext-pcie và cocotb-bus hoạt động trên cocotb 2.1.0.

import sys
import types
import cocotb

# 1. Map cocotb.fork to cocotb.start_soon if needed
if not hasattr(cocotb, "fork") and hasattr(cocotb, "start_soon"):
    cocotb.fork = cocotb.start_soon

# 2. Map cocotb.coroutine as a pass-through decorator for async def
if not hasattr(cocotb, "coroutine"):
    def coroutine_compat(func):
        return func
    cocotb.coroutine = coroutine_compat

# 3. Ensure cocotb.result.TestFailure is available
if not hasattr(cocotb, "result"):
    res_mod = types.ModuleType("cocotb.result")
    sys.modules["cocotb.result"] = res_mod
    cocotb.result = res_mod

if not hasattr(cocotb.result, "TestFailure"):
    class TestFailure(AssertionError):
        """Compatibility wrapper for TestFailure exception."""
        pass
    cocotb.result.TestFailure = TestFailure

if not hasattr(cocotb.result, "TestSuccess"):
    class TestSuccess(Exception):
        """Compatibility wrapper for TestSuccess exception."""
        pass
    cocotb.result.TestSuccess = TestSuccess

# 4. Ensure cocotb.binary and BinaryValue compatibility
try:
    import cocotb.binary
except ImportError:
    try:
        import cocotb.types
        bin_mod = types.ModuleType("cocotb.binary")
        if hasattr(cocotb.types, "LogicArray"):
            bin_mod.BinaryValue = cocotb.types.LogicArray
        elif hasattr(cocotb.types, "BinaryValue"):
            bin_mod.BinaryValue = cocotb.types.BinaryValue
        else:
            class DummyBinaryValue:
                def __init__(self, value=0, n_bits=None, **kwargs):
                    self.integer = int(value) if isinstance(value, (int, str)) and str(value).isdigit() else 0
                    self.n_bits = n_bits
            bin_mod.BinaryValue = DummyBinaryValue
        sys.modules["cocotb.binary"] = bin_mod
        cocotb.binary = bin_mod
    except Exception:
        pass
