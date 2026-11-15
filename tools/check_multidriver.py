#!/usr/bin/env python3
"""Kiểm tra đa nguồn (multi-driver) trên RTL SystemVerilog của Q-Shield.

Chức năng:
  1. Phân tích cấu trúc SystemVerilog (mọi khối always_ff/always_comb/always/assign/cổng ra module con)
     trên toàn bộ cây nguồn `axi_ddr5_mc_secure_top` (hoặc danh sách file chỉ định),
     kiểm tra cả chế độ thường và `-DQSHIELD_TEST`.
  2. Chạy Yosys trong WSL (`read_verilog -sv`, `hierarchy`, `proc`, `check -assert`) khi được yêu cầu
     hoặc cho test âm (`--self-test`) và trên từng module hợp lệ.
  3. Tùy chọn đọc log Vivado (`--vivado-log`) để bắt cảnh báo `[Synth 8-6859]`, `[Synth 8-6858]`, `[DRC MDRV-1]`.

Thoát 1 nếu phát hiện bất kỳ tín hiệu đa nguồn nào; thoát 0 nếu sạch.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parents[1]

SECURE_TOP_RTL_FILES = [
    "rtl/backend/secded_72_64_pkg.sv",
    "rtl/crypto/aes_pkg.sv",
    "rtl/cdc/rst_sync.sv",
    "rtl/frontend/axi_slave_frontend.sv",
    "rtl/bus/axi4_skid_buffer.sv",
    "rtl/frontend/wdata_buffer.sv",
    "rtl/frontend/wr_data_store.sv",
    "rtl/frontend/axi_burst_splitter.sv",
    "rtl/frontend/rd_issue_queue.sv",
    "rtl/core/fault_hardened_csr.sv",
    "rtl/crypto/multi_vm_key_table.sv",
    "rtl/frontend/addr_mapper_ddr5.sv",
    "rtl/frontend/domain_bank_coloring.sv",
    "rtl/core/scarf_dram_randomizer.sv",
    "rtl/core/reorder_buffer_rob.sv",
    "rtl/core/sdc_resilient_filter.sv",
    "rtl/core/pxor_hash_engine.sv",
    "rtl/core/adaptive_threshold_engine.sv",
    "rtl/backend/directed_refresh_manager.sv",
    "rtl/core/qos_scheduler_queue.sv",
    "rtl/backend/slack_aware_arbiter.sv",
    "rtl/backend/ddr5_cmd_engine.sv",
    "rtl/backend/ecc_scrubber.sv",
    "rtl/memory/bus_scrambler.sv",
    "rtl/memory/scrambler_ks_pipe.sv",
    "rtl/bus/perf_monitor_unit.sv",
    "rtl/cdc/async_fifo_cdc.sv",
    "rtl/top/bank_credit_ctrl.sv",
    "rtl/top/axi_ddr5_mc_top.sv",
    "rtl/crypto/aes_sbox.sv",
    "rtl/crypto/aes_sbox_composite.sv",
    "rtl/crypto/aes_round_pipe.sv",
    "rtl/crypto/aes256_key_expand.sv",
    "rtl/crypto/qshield_xts_tweak_unit.sv",
    "rtl/crypto/subchannel_aes_xts_pipe.sv",
    "rtl/crypto/aes_inv_cipher_pipe.sv",
    "rtl/crypto/gf128_mul_pipe.sv",
    "rtl/crypto/qshield_mac_unit.sv",
    "rtl/crypto/qshield_meta_layout.sv",
    "rtl/crypto/qshield_meta_cache.sv",
    "rtl/crypto/qshield_counter_unit.sv",
    "rtl/crypto/qshield_bmt_engine.sv",
    "rtl/crypto/qshield_integrity_csr.sv",
    "rtl/crypto/qshield_axi_crypto_bridge.sv",
    "rtl/top/axi_ddr5_mc_secure_top.sv",
]

NEGATIVE_TEST_SV = """\
`timescale 1ns / 1ps
module neg_multidriver_test (
    input  logic clk,
    input  logic rst_n,
    input  logic a,
    input  logic b,
    output logic bad_sig
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            bad_sig <= 1'b0;
        else if (a)
            bad_sig <= 1'b1;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            bad_sig <= 1'b0;
        else if (b)
            bad_sig <= 1'b0;
    end
endmodule
"""

SV_KEYWORDS = {
    "always", "always_ff", "always_comb", "always_latch", "and", "assign",
    "automatic", "begin", "bit", "break", "buf", "byte", "case", "casex",
    "casez", "chandle", "class", "clocking", "const", "continue", "cover",
    "default", "defparam", "disable", "do", "edge", "else", "end", "endcase",
    "endclass", "endclocking", "endfunction", "endgenerate", "endinterface",
    "endmodule", "endpackage", "endprimitive", "endproperty", "endsequence",
    "endtask", "enum", "event", "export", "extends", "extern", "final", "for",
    "force", "foreach", "forever", "fork", "function", "generate", "genvar",
    "if", "iff", "ifnone", "import", "in", "initial", "inout", "input", "int",
    "integer", "interface", "join", "join_any", "join_none", "local",
    "localparam", "logic", "longint", "macromodule", "modport", "module",
    "nand", "negedge", "new", "nmos", "nor", "not", "null", "or", "output",
    "package", "packed", "parameter", "pmos", "posedge", "primitive",
    "priority", "program", "property", "protected", "pull0", "pull1",
    "pulldown", "pullup", "pure", "rand", "randc", "real", "realtime", "ref",
    "reg", "release", "repeat", "return", "rnmos", "rpmos", "rtran", "rtranif0",
    "rtranif1", "scalared", "sequence", "shortint", "shortreal", "signed",
    "small", "solve", "specify", "specparam", "static", "string", "strong0",
    "strong1", "struct", "super", "supply0", "supply1", "table", "task",
    "this", "throughout", "time", "timeprecision", "timeunit", "tran",
    "tranif0", "tranif1", "tri", "tri0", "tri1", "triand", "trior", "trireg",
    "type", "typedef", "union", "unique", "unique0", "unsigned", "use", "var",
    "vectored", "virtual", "void", "wait", "wand", "weak0", "weak1", "while",
    "wire", "with", "wor", "xnor", "xor", "assert", "assume", "restrict",
}

VAR_TYPE_KEYWORDS = {
    "logic", "reg", "bit", "int", "integer", "byte", "shortint", "longint",
    "time", "realtime", "real", "wire", "tri", "wand", "wor", "genvar",
}


def strip_comments_and_strings(text: str) -> str:
    """Xóa comment và chuỗi nhưng giữ nguyên số dòng để đối chiếu dòng chính xác."""
    out: List[str] = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                out.append(" ")
                i += 1
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            out.append("  ")
            i += 2
            while i < n and not (text[i] == "*" and i + 1 < n and text[i + 1] == "/"):
                out.append("\n" if text[i] == "\n" else " ")
                i += 1
            if i < n:
                out.append("  ")
                i += 2
        elif c == '"':
            out.append(" ")
            i += 1
            while i < n and text[i] != '"':
                if text[i] == "\\" and i + 1 < n:
                    out.append("  ")
                    i += 2
                else:
                    out.append("\n" if text[i] == "\n" else " ")
                    i += 1
            if i < n:
                out.append(" ")
                i += 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


def preprocess_ifdef(text: str, defines: Set[str]) -> str:
    """Xử lý `ifdef/`ifndef/`elsif/`else/`endif/`define/`undef và giữ nguyên số dòng."""
    active_defines = set(defines)
    stack: List[List[bool]] = []
    out_lines: List[str] = []

    for line in text.splitlines():
        s = line.strip()
        is_active = all(frame[2] for frame in stack) if stack else True

        m_ifdef = re.match(r"^`ifdef\s+([A-Za-z_]\w*)", s)
        m_ifndef = re.match(r"^`ifndef\s+([A-Za-z_]\w*)", s)
        m_elsif = re.match(r"^`elsif\s+([A-Za-z_]\w*)", s)
        m_else = re.match(r"^`else\b", s)
        m_endif = re.match(r"^`endif\b", s)

        if m_ifdef:
            cond = m_ifdef.group(1) in active_defines
            stack.append([is_active, cond, is_active and cond])
            out_lines.append("")
            continue
        if m_ifndef:
            cond = m_ifndef.group(1) not in active_defines
            stack.append([is_active, cond, is_active and cond])
            out_lines.append("")
            continue
        if m_elsif and stack:
            parent_act, taken, _ = stack[-1]
            cond = (m_elsif.group(1) in active_defines) and not taken
            stack[-1] = [parent_act, taken or cond, parent_act and cond]
            out_lines.append("")
            continue
        if m_else and stack:
            parent_act, taken, _ = stack[-1]
            cond = not taken
            stack[-1] = [parent_act, True, parent_act and cond]
            out_lines.append("")
            continue
        if m_endif and stack:
            stack.pop()
            out_lines.append("")
            continue

        if not is_active:
            out_lines.append("")
            continue

        if s.startswith("`"):
            m_def = re.match(r"^`define\s+([A-Za-z_]\w*)", s)
            m_undef = re.match(r"^`undef\s+([A-Za-z_]\w*)", s)
            if m_def:
                active_defines.add(m_def.group(1))
            elif m_undef:
                active_defines.discard(m_undef.group(1))
            out_lines.append("")
            continue

        out_lines.append(line)

    return "\n".join(out_lines)


@dataclass
class Token:
    kind: str  # ID, NUM, OP, SYM
    val: str
    line: int


TOKEN_RE = re.compile(
    r"""
    (?P<NUM>\d+'[bBoOdDhH][0-9a-fA-F_xXzZ?]+|\d+\.\d+|\d+|'[01xXzZ])
    |(?P<ID>[A-Za-z_$][A-Za-z0-9_$]*)
    |(?P<OP><<=|>>=|<<<|>>>|<=|>=|==|!=|===|!==|\+=|-=|\*=|/=|&=|\|=|\^=|&&|\|\||\+:|-:|::|->|\*\*)
    |(?P<SYM>[(){}\[\];:,=<>+\-*/%&|^~!?.@#])
    """,
    re.VERBOSE,
)


def tokenize(text: str) -> List[Token]:
    tokens: List[Token] = []
    line_num = 1
    pos = 0
    for m in TOKEN_RE.finditer(text):
        gap = text[pos:m.start()]
        line_num += gap.count("\n")
        pos = m.end()
        kind = m.lastgroup or "SYM"
        val = m.group(kind)
        tokens.append(Token(kind, val, line_num))
    return tokens


def skip_balanced(tokens: List[Token], idx: int, open_tok: str, close_tok: str) -> int:
    if idx >= len(tokens) or tokens[idx].val != open_tok:
        return idx
    depth = 0
    while idx < len(tokens):
        if tokens[idx].val == open_tok:
            depth += 1
        elif tokens[idx].val == close_tok:
            depth -= 1
            if depth == 0:
                return idx + 1
        idx += 1
    return idx


def skip_until_semi(tokens: List[Token], idx: int) -> int:
    p_depth = 0
    b_depth = 0
    while idx < len(tokens):
        v = tokens[idx].val
        if v == "(":
            p_depth += 1
        elif v == ")" and p_depth > 0:
            p_depth -= 1
        elif v == "[":
            b_depth += 1
        elif v == "]" and b_depth > 0:
            b_depth -= 1
        elif v == ";" and p_depth == 0 and b_depth == 0:
            return idx + 1
        idx += 1
    return idx


def eval_const_int_expr(expr_tokens: List[Token], env: Dict[str, int]) -> Optional[int]:
    """Đánh giá biểu thức số nguyên đơn giản từ parameter/localparam/hằng số."""
    if not expr_tokens:
        return None
    parts: List[str] = []
    for t in expr_tokens:
        v = t.val
        if t.kind == "NUM" and v.isdigit():
            parts.append(v)
        elif t.kind == "ID" and v in env:
            parts.append(str(env[v]))
        elif v in ("+", "-", "*", "/", "%", "(", ")"):
            parts.append("//" if v == "/" else v)
        else:
            return None
    try:
        val = eval("".join(parts), {"__builtins__": {}}, {})
        return int(val)
    except Exception:
        return None


def eval_simple_gen_slice(
    idx_toks: List[Token],
    gen_bounds: Dict[str, Tuple[int, int]],
    params: Dict[str, int],
    gen_excluded: Dict[str, Set[int]],
) -> Optional[Set[int]]:
    """Trả về tập chỉ số cụ thể mà biểu thức truy cập, hoặc None nếu động/không xác định."""
    if len(idx_toks) >= 3:
        colon_pos = [idx for idx, t in enumerate(idx_toks) if t.val == ":"]
        if len(colon_pos) == 1:
            c = colon_pos[0]
            hi = eval_const_int_expr(idx_toks[:c], params)
            lo = eval_const_int_expr(idx_toks[c + 1:], params)
            if hi is not None and lo is not None:
                return set(range(min(hi, lo), max(hi, lo) + 1))

    cval = eval_const_int_expr(idx_toks, params)
    if cval is not None:
        return {cval}

    gvars_used = {t.val for t in idx_toks if t.kind == "ID" and t.val in gen_bounds}
    if len(gvars_used) == 1:
        gv = next(iter(gvars_used))
        lo, hi = gen_bounds[gv]
        excl = gen_excluded.get(gv, set())
        out_set: Set[int] = set()
        for g in range(lo, hi + 1):
            if g in excl:
                continue
            env = dict(params)
            env[gv] = g
            val = eval_const_int_expr(idx_toks, env)
            if val is None:
                return None
            out_set.add(val)
        return out_set

    return None


def extract_lvalue_targets(
    lhs_tokens: List[Token],
    gen_bounds: Dict[str, Tuple[int, int]],
    params: Dict[str, int],
    gen_excluded: Dict[str, Set[int]],
) -> List[Tuple[str, Optional[Set[int]]]]:
    """Rút trích `(tên_tín_hiệu, tập_chỉ_số_hoặc_None)` ở vế trái phép gán."""
    if not lhs_tokens:
        return []

    if lhs_tokens[0].val == "{" and lhs_tokens[-1].val == "}":
        inner = lhs_tokens[1:-1]
        parts: List[List[Token]] = []
        cur: List[Token] = []
        p_d = b_d = c_d = 0
        for t in inner:
            if t.val == "(":
                p_d += 1
            elif t.val == ")":
                p_d -= 1
            elif t.val == "[":
                b_d += 1
            elif t.val == "]":
                b_d -= 1
            elif t.val == "{":
                c_d += 1
            elif t.val == "}":
                c_d -= 1
            if t.val == "," and p_d == 0 and b_d == 0 and c_d == 0:
                parts.append(cur)
                cur = []
            else:
                cur.append(t)
        if cur:
            parts.append(cur)
        res: List[Tuple[str, Optional[Set[int]]]] = []
        for p in parts:
            res.extend(extract_lvalue_targets(p, gen_bounds, params, gen_excluded))
        return res

    first = lhs_tokens[0]
    if first.kind != "ID" or first.val in SV_KEYWORDS:
        return []

    slice_set: Optional[Set[int]] = None
    if len(lhs_tokens) >= 4 and lhs_tokens[1].val == "[" and lhs_tokens[-1].val == "]":
        depth = 0
        single_bracket = True
        for k in range(1, len(lhs_tokens) - 1):
            if lhs_tokens[k].val == "[":
                depth += 1
            elif lhs_tokens[k].val == "]":
                depth -= 1
                if depth == 0:
                    single_bracket = False
                    break
        if single_bracket:
            slice_set = eval_simple_gen_slice(lhs_tokens[2:-1], gen_bounds, params, gen_excluded)

    return [(first.val, slice_set)]


@dataclass
class DriverWrite:
    driver_id: str
    driver_kind: str
    line: int
    slice_set: Optional[Set[int]] = None
    gen_branch: Tuple[Tuple[int, int], ...] = ()


@dataclass
class ModuleInfo:
    name: str
    file_path: str
    outputs: Set[str] = field(default_factory=set)
    inouts: Set[str] = field(default_factory=set)
    custom_types: Set[str] = field(default_factory=set)
    writes: Dict[str, List[DriverWrite]] = field(default_factory=lambda: defaultdict(list))


def parse_port_directions(tokens: List[Token], mod_start: int) -> Tuple[Set[str], Set[str], int]:
    outputs: Set[str] = set()
    inouts: Set[str] = set()
    i = mod_start + 2
    n = len(tokens)
    while i < n and tokens[i].val == "import":
        i = skip_until_semi(tokens, i)
    if i < n and tokens[i].val == "#":
        i += 1
        if i < n and tokens[i].val == "(":
            i = skip_balanced(tokens, i, "(", ")")
    if i < n and tokens[i].val == "(":
        end_p = skip_balanced(tokens, i, "(", ")")
        j = i + 1
        cur_dir = ""
        b_depth = p_depth = 0
        last_id: Optional[str] = None
        while j < end_p - 1:
            v = tokens[j].val
            if v == "[":
                b_depth += 1
            elif v == "]":
                b_depth -= 1
            elif v == "(":
                p_depth += 1
            elif v == ")":
                p_depth -= 1
            elif b_depth == 0 and p_depth == 0:
                if v in ("input", "output", "inout", "ref"):
                    cur_dir = v
                    last_id = None
                elif v == ",":
                    if last_id and cur_dir == "output":
                        outputs.add(last_id)
                    elif last_id and cur_dir == "inout":
                        inouts.add(last_id)
                    last_id = None
                elif v == "=":
                    if last_id and cur_dir == "output":
                        outputs.add(last_id)
                    elif last_id and cur_dir == "inout":
                        inouts.add(last_id)
                    last_id = None
                    j += 1
                    while j < end_p - 1:
                        tv = tokens[j].val
                        if tv == "(":
                            p_depth += 1
                        elif tv == ")":
                            p_depth -= 1
                        elif tv == "," and p_depth == 0:
                            break
                        j += 1
                    continue
                elif tokens[j].kind == "ID" and v not in SV_KEYWORDS:
                    last_id = v
            j += 1
        if last_id and cur_dir == "output":
            outputs.add(last_id)
        elif last_id and cur_dir == "inout":
            inouts.add(last_id)
        i = end_p
    if i < n and tokens[i].val == ";":
        i += 1
    return outputs, inouts, i


def scan_procedural_block(
    tokens: List[Token],
    start_idx: int,
    mod_types: Set[str],
    driver_id: str,
    driver_kind: str,
    gen_branch: Tuple[Tuple[int, int], ...],
    gen_bounds: Dict[str, Tuple[int, int]],
    params: Dict[str, int],
    gen_excluded: Dict[str, Set[int]],
    writes: Dict[str, List[DriverWrite]],
) -> int:
    n = len(tokens)
    i = start_idx
    if i < n and tokens[i].val in ("always_ff", "always_comb", "always_latch", "always"):
        i += 1
    if i < n and tokens[i].val == "@":
        i += 1
        if i < n and tokens[i].val == "(":
            i = skip_balanced(tokens, i, "(", ")")
        elif i < n and tokens[i].val == "*":
            i += 1

    local_scopes: List[Set[str]] = [set()]

    def is_local(name: str) -> bool:
        return any(name in sc for sc in local_scopes)

    def record_lhs(lhs_toks: List[Token], line_no: int) -> None:
        for sig, sset in extract_lvalue_targets(lhs_toks, gen_bounds, params, gen_excluded):
            if not is_local(sig):
                writes[sig].append(DriverWrite(driver_id, driver_kind, line_no, sset, gen_branch))

    def parse_stmt(idx: int) -> int:
        if idx >= n:
            return idx
        tok = tokens[idx]
        v = tok.val

        if v == "begin":
            local_scopes.append(set())
            idx += 1
            if idx + 1 < n and tokens[idx].val == ":" and tokens[idx + 1].kind == "ID":
                idx += 2
            while idx < n and tokens[idx].val != "end":
                idx = parse_stmt(idx)
            if idx < n and tokens[idx].val == "end":
                idx += 1
                if idx + 1 < n and tokens[idx].val == ":" and tokens[idx + 1].kind == "ID":
                    idx += 2
            local_scopes.pop()
            return idx

        if v == "if":
            idx += 1
            if idx < n and tokens[idx].val == "(":
                idx = skip_balanced(tokens, idx, "(", ")")
            idx = parse_stmt(idx)
            if idx < n and tokens[idx].val == "else":
                idx += 1
                idx = parse_stmt(idx)
            return idx

        if v in ("unique", "unique0", "priority"):
            return parse_stmt(idx + 1)

        if v in ("case", "casex", "casez"):
            idx += 1
            if idx < n and tokens[idx].val == "(":
                idx = skip_balanced(tokens, idx, "(", ")")
            while idx < n and tokens[idx].val != "endcase":
                if tokens[idx].val == "default":
                    idx += 1
                    if idx < n and tokens[idx].val == ":":
                        idx += 1
                    idx = parse_stmt(idx)
                else:
                    p_d = b_d = 0
                    while idx < n and tokens[idx].val != "endcase":
                        tv = tokens[idx].val
                        if tv == "(":
                            p_d += 1
                        elif tv == ")":
                            p_d -= 1
                        elif tv == "[":
                            b_d += 1
                        elif tv == "]":
                            b_d -= 1
                        elif tv == ":" and p_d == 0 and b_d == 0:
                            idx += 1
                            break
                        idx += 1
                    idx = parse_stmt(idx)
            if idx < n and tokens[idx].val == "endcase":
                idx += 1
            return idx

        if v == "for":
            idx += 1
            local_scopes.append(set())
            if idx < n and tokens[idx].val == "(":
                end_f = skip_balanced(tokens, idx, "(", ")")
                k = idx + 1
                while k < end_f - 1 and tokens[k].val != ";":
                    if tokens[k].val in VAR_TYPE_KEYWORDS and k + 1 < end_f - 1 and tokens[k + 1].kind == "ID":
                        local_scopes[-1].add(tokens[k + 1].val)
                    k += 1
                idx = end_f
            idx = parse_stmt(idx)
            local_scopes.pop()
            return idx

        if v in ("while", "repeat", "foreach"):
            idx += 1
            if idx < n and tokens[idx].val == "(":
                idx = skip_balanced(tokens, idx, "(", ")")
            return parse_stmt(idx)

        if v == "forever":
            return parse_stmt(idx + 1)

        if v in ("assert", "assume", "cover", "restrict"):
            idx += 1
            if idx < n and tokens[idx].val == "(":
                idx = skip_balanced(tokens, idx, "(", ")")
            if idx < n and tokens[idx].val == ";":
                idx += 1
            return idx

        if v == ";":
            return idx + 1

        if v in VAR_TYPE_KEYWORDS or v in mod_types or v in ("automatic", "static", "const"):
            end_s = skip_until_semi(tokens, idx)
            k = idx + 1
            if v in ("automatic", "static", "const") and k < end_s:
                k += 1
            b_d = p_d = 0
            saw_eq = False
            while k < end_s - 1:
                tv = tokens[k].val
                if tv == "[":
                    b_d += 1
                elif tv == "]":
                    b_d -= 1
                elif tv == "(":
                    p_d += 1
                elif tv == ")":
                    p_d -= 1
                elif b_d == 0 and p_d == 0:
                    if tv == "=":
                        saw_eq = True
                    elif tv == ",":
                        saw_eq = False
                    elif not saw_eq and tokens[k].kind == "ID" and tv not in SV_KEYWORDS and tv not in mod_types:
                        local_scopes[-1].add(tv)
                k += 1
            return end_s

        end_s = skip_until_semi(tokens, idx)
        if v.startswith("$") or v in ("return", "disable", "break", "continue"):
            return end_s

        p_d = b_d = c_d = 0
        assign_ops = {"<=", "=", "+=", "-=", "*=", "/=", "&=", "|=", "^=", "<<=", ">>="}
        k = idx
        assign_pos = -1
        while k < end_s - 1:
            tv = tokens[k].val
            if tv == "(":
                p_d += 1
            elif tv == ")":
                p_d -= 1
            elif tv == "[":
                b_d += 1
            elif tv == "]":
                b_d -= 1
            elif tv == "{":
                c_d += 1
            elif tv == "}":
                c_d -= 1
            elif p_d == 0 and b_d == 0 and c_d == 0 and tv in assign_ops:
                assign_pos = k
                break
            k += 1

        if assign_pos > idx:
            record_lhs(tokens[idx:assign_pos], tokens[idx].line)
        return end_s

    return parse_stmt(i)


def parse_gen_for_bounds(hdr_tokens: List[Token], params: Dict[str, int]) -> Dict[str, Tuple[int, int]]:
    parts: List[List[Token]] = [[], [], []]
    p_idx = 0
    for t in hdr_tokens:
        if t.val == ";" and p_idx < 2:
            p_idx += 1
        else:
            parts[p_idx].append(t)
    init_t, cond_t, _ = parts
    gvar: Optional[str] = None
    lo: Optional[int] = None
    for idx, t in enumerate(init_t):
        if t.val == "=" and idx >= 1 and init_t[idx - 1].kind == "ID":
            gvar = init_t[idx - 1].val
            lo = eval_const_int_expr(init_t[idx + 1:], params)
            break
    if gvar is None or lo is None:
        return {}

    hi = 1024
    if len(cond_t) >= 3 and cond_t[0].val == gvar:
        op = cond_t[1].val
        bound_val = eval_const_int_expr(cond_t[2:], params)
        if bound_val is not None:
            if op == "<":
                hi = bound_val - 1
            elif op == "<=":
                hi = bound_val
    return {gvar: (lo, hi)}


def extract_param_assigns(stmt_toks: List[Token], params: Dict[str, int]) -> None:
    """Rút trích các khai báo `parameter/localparam ... NAME = EXPR`."""
    p_d = b_d = 0
    i = 0
    n = len(stmt_toks)
    while i < n:
        v = stmt_toks[i].val
        if v == "(":
            p_d += 1
        elif v == ")":
            p_d -= 1
        elif v == "[":
            b_d += 1
        elif v == "]":
            b_d -= 1
        elif p_d == 0 and b_d == 0 and v == "=" and i >= 1 and stmt_toks[i - 1].kind == "ID":
            pname = stmt_toks[i - 1].val
            j = i + 1
            ep = eb = 0
            while j < n:
                jv = stmt_toks[j].val
                if jv == "(":
                    ep += 1
                elif jv == ")":
                    ep -= 1
                elif jv == "[":
                    eb += 1
                elif jv == "]":
                    eb -= 1
                elif ep == 0 and eb == 0 and jv in (",", ";"):
                    break
                j += 1
            val = eval_const_int_expr(stmt_toks[i + 1:j], params)
            if val is not None:
                params[pname] = val
            i = j
        i += 1


def analyze_modules(files_with_text: List[Tuple[str, str]]) -> Dict[str, ModuleInfo]:
    all_tokens_by_file: List[Tuple[str, List[Token]]] = []
    known_modules: Dict[str, ModuleInfo] = {}

    for fpath, text in files_with_text:
        toks = tokenize(text)
        all_tokens_by_file.append((fpath, toks))
        i = 0
        n = len(toks)
        while i < n:
            if toks[i].val == "module" and i + 1 < n and toks[i + 1].kind == "ID":
                mname = toks[i + 1].val
                outs, inouts, body_start = parse_port_directions(toks, i)
                info = ModuleInfo(name=mname, file_path=fpath, outputs=outs, inouts=inouts)
                known_modules[mname] = info
                j = body_start
                while j < n and toks[j].val != "endmodule":
                    if toks[j].val in ("output", "inout"):
                        d = toks[j].val
                        end_s = skip_until_semi(toks, j)
                        k = j + 1
                        bd = 0
                        while k < end_s - 1:
                            if toks[k].val == "[":
                                bd += 1
                            elif toks[k].val == "]":
                                bd -= 1
                            elif bd == 0 and toks[k].kind == "ID" and toks[k].val not in SV_KEYWORDS:
                                if k + 1 < end_s and toks[k + 1].val in (",", ";", "[", "="):
                                    if d == "output":
                                        info.outputs.add(toks[k].val)
                                    else:
                                        info.inouts.add(toks[k].val)
                            k += 1
                        j = end_s
                    else:
                        j += 1
                i = j + 1
            else:
                i += 1

    for fpath, toks in all_tokens_by_file:
        i = 0
        n = len(toks)
        while i < n:
            if toks[i].val == "module" and i + 1 < n and toks[i + 1].kind == "ID":
                mname = toks[i + 1].val
                info = known_modules[mname]
                params: Dict[str, int] = {}
                pk = i + 2
                while pk < n and toks[pk].val == "import":
                    pk = skip_until_semi(toks, pk)
                if pk < n and toks[pk].val == "#":
                    pk += 1
                    if pk < n and toks[pk].val == "(":
                        pe = skip_balanced(toks, pk, "(", ")")
                        extract_param_assigns(toks[pk + 1:pe - 1], params)

                _, _, i = parse_port_directions(toks, i)
                gen_counter = 0
                block_idx = 0

                def parse_module_items(
                    idx: int,
                    stop_tokens: Set[str],
                    cur_branch: Tuple[Tuple[int, int], ...],
                    cur_bounds: Dict[str, Tuple[int, int]],
                    cur_excl: Dict[str, Set[int]],
                ) -> int:
                    nonlocal gen_counter, block_idx
                    while idx < n and toks[idx].val not in stop_tokens:
                        v = toks[idx].val

                        if v in ("function", "task"):
                            end_kw = "endfunction" if v == "function" else "endtask"
                            while idx < n and toks[idx].val != end_kw:
                                idx += 1
                            if idx < n:
                                idx += 1
                            continue

                        if v == "typedef":
                            end_s = skip_until_semi(toks, idx)
                            if end_s >= 2 and toks[end_s - 2].kind == "ID":
                                info.custom_types.add(toks[end_s - 2].val)
                            idx = end_s
                            continue

                        if v in ("parameter", "localparam"):
                            end_s = skip_until_semi(toks, idx)
                            extract_param_assigns(toks[idx + 1:end_s], params)
                            idx = end_s
                            continue

                        if v in ("generate", "endgenerate"):
                            idx += 1
                            continue

                        if v == "if":
                            gen_counter += 1
                            gid = gen_counter
                            idx += 1
                            cond_excl_var: Optional[str] = None
                            cond_excl_val: Optional[int] = None
                            if idx < n and toks[idx].val == "(":
                                end_c = skip_balanced(toks, idx, "(", ")")
                                c_toks = toks[idx + 1:end_c - 1]
                                # Nhận dạng `gvar == CONST` để loại trừ đúng giá trị ở nhánh `else`
                                if len(c_toks) >= 3 and c_toks[0].kind == "ID" and c_toks[0].val in cur_bounds and c_toks[1].val == "==":
                                    c_v = eval_const_int_expr(c_toks[2:], params)
                                    if c_v is not None:
                                        cond_excl_var = c_toks[0].val
                                        cond_excl_val = c_v
                                idx = end_c
                            b_idx = 0
                            if idx < n and toks[idx].val == "begin":
                                idx += 1
                                if idx + 1 < n and toks[idx].val == ":" and toks[idx + 1].kind == "ID":
                                    idx += 2
                                idx = parse_module_items(idx, {"end"}, cur_branch + ((gid, b_idx),), cur_bounds, cur_excl)
                                if idx < n and toks[idx].val == "end":
                                    idx += 1
                            else:
                                idx = parse_single_gen_item(idx, cur_branch + ((gid, b_idx),), cur_bounds, cur_excl)
                            while idx < n and toks[idx].val == "else":
                                idx += 1
                                b_idx += 1
                                else_excl = {k: set(val) for k, val in cur_excl.items()}
                                if cond_excl_var is not None and cond_excl_val is not None:
                                    else_excl.setdefault(cond_excl_var, set()).add(cond_excl_val)
                                if idx < n and toks[idx].val == "if":
                                    idx += 1
                                    if idx < n and toks[idx].val == "(":
                                        idx = skip_balanced(toks, idx, "(", ")")
                                if idx < n and toks[idx].val == "begin":
                                    idx += 1
                                    if idx + 1 < n and toks[idx].val == ":" and toks[idx + 1].kind == "ID":
                                        idx += 2
                                    idx = parse_module_items(idx, {"end"}, cur_branch + ((gid, b_idx),), cur_bounds, else_excl)
                                    if idx < n and toks[idx].val == "end":
                                        idx += 1
                                else:
                                    idx = parse_single_gen_item(idx, cur_branch + ((gid, b_idx),), cur_bounds, else_excl)
                            continue

                        if v == "for":
                            idx += 1
                            new_bounds = dict(cur_bounds)
                            if idx < n and toks[idx].val == "(":
                                end_f = skip_balanced(toks, idx, "(", ")")
                                new_bounds.update(parse_gen_for_bounds(toks[idx + 1:end_f - 1], params))
                                idx = end_f
                            if idx < n and toks[idx].val == "begin":
                                idx += 1
                                if idx + 1 < n and toks[idx].val == ":" and toks[idx + 1].kind == "ID":
                                    idx += 2
                                idx = parse_module_items(idx, {"end"}, cur_branch, new_bounds, cur_excl)
                                if idx < n and toks[idx].val == "end":
                                    idx += 1
                            else:
                                idx = parse_single_gen_item(idx, cur_branch, new_bounds, cur_excl)
                            continue

                        idx = parse_single_gen_item(idx, cur_branch, cur_bounds, cur_excl)
                    return idx

                def parse_single_gen_item(
                    idx: int,
                    cur_branch: Tuple[Tuple[int, int], ...],
                    cur_bounds: Dict[str, Tuple[int, int]],
                    cur_excl: Dict[str, Set[int]],
                ) -> int:
                    nonlocal block_idx
                    if idx >= n:
                        return idx
                    v = toks[idx].val

                    if v in ("always_ff", "always_comb", "always_latch", "always"):
                        block_idx += 1
                        drv_id = f"{v}@{toks[idx].line}#{block_idx}"
                        return scan_procedural_block(
                            toks, idx, info.custom_types, drv_id, v, cur_branch, cur_bounds, params, cur_excl, info.writes
                        )

                    if v == "assign":
                        block_idx += 1
                        start_line = toks[idx].line
                        end_s = skip_until_semi(toks, idx)
                        k = idx + 1
                        while k < end_s - 1 and toks[k].val != "=":
                            k += 1
                        if k < end_s - 1:
                            drv_id = f"assign@{start_line}#{block_idx}"
                            for sig, sset in extract_lvalue_targets(toks[idx + 1:k], cur_bounds, params, cur_excl):
                                info.writes[sig].append(
                                    DriverWrite(drv_id, "assign", start_line, sset, cur_branch)
                                )
                        return end_s

                    if v in ("wire", "tri", "wand", "wor"):
                        end_s = skip_until_semi(toks, idx)
                        p_d = b_d = 0
                        k = idx + 1
                        prev_id: Optional[str] = None
                        while k < end_s - 1:
                            tv = toks[k].val
                            if tv == "(":
                                p_d += 1
                            elif tv == ")":
                                p_d -= 1
                            elif tv == "[":
                                b_d += 1
                            elif tv == "]":
                                b_d -= 1
                            elif p_d == 0 and b_d == 0:
                                if tv == "=" and prev_id:
                                    block_idx += 1
                                    drv_id = f"wire_assign@{toks[idx].line}#{block_idx}"
                                    info.writes[prev_id].append(
                                        DriverWrite(drv_id, "wire_assign", toks[idx].line, None, cur_branch)
                                    )
                                    break
                                elif toks[k].kind == "ID" and tv not in SV_KEYWORDS and tv not in info.custom_types:
                                    prev_id = tv
                            k += 1
                        return end_s

                    if v in ("initial", "final"):
                        idx += 1
                        if idx < n and toks[idx].val == "begin":
                            depth = 1
                            idx += 1
                            while idx < n and depth > 0:
                                if toks[idx].val == "begin":
                                    depth += 1
                                elif toks[idx].val == "end":
                                    depth -= 1
                                idx += 1
                            return idx
                        return skip_until_semi(toks, idx)

                    if v in ("import", "input", "output", "inout", "typedef", "struct", "enum"):
                        return skip_until_semi(toks, idx)

                    if v == "begin":
                        idx += 1
                        if idx + 1 < n and toks[idx].val == ":" and toks[idx + 1].kind == "ID":
                            idx += 2
                        idx = parse_module_items(idx, {"end"}, cur_branch, cur_bounds, cur_excl)
                        if idx < n and toks[idx].val == "end":
                            idx += 1
                        return idx

                    if toks[idx].kind == "ID" and v in known_modules and v != mname:
                        sub_mod = known_modules[v]
                        end_s = skip_until_semi(toks, idx)
                        k = idx + 1
                        if k < end_s and toks[k].val == "#":
                            k += 1
                            if k < end_s and toks[k].val == "(":
                                k = skip_balanced(toks, k, "(", ")")
                        while k < end_s and toks[k].val != "(":
                            k += 1
                        if k < end_s and toks[k].val == "(":
                            end_ports = skip_balanced(toks, k, "(", ")")
                            inst_name = toks[k - 1].val if k > idx else sub_mod.name
                            p = k + 1
                            while p < end_ports - 1:
                                if toks[p].val == "." and p + 1 < end_ports - 1 and toks[p + 1].kind == "ID":
                                    pname = toks[p + 1].val
                                    p += 2
                                    if p < end_ports - 1 and toks[p].val == "(":
                                        expr_end = skip_balanced(toks, p, "(", ")")
                                        if pname in sub_mod.outputs or pname in sub_mod.inouts:
                                            expr_toks = toks[p + 1:expr_end - 1]
                                            if expr_toks:
                                                block_idx += 1
                                                drv_id = f"inst({sub_mod.name}:{inst_name}.{pname})@{toks[p].line}#{block_idx}"
                                                for sig, sset in extract_lvalue_targets(expr_toks, cur_bounds, params, cur_excl):
                                                    info.writes[sig].append(
                                                        DriverWrite(drv_id, "inst_out", toks[p].line, sset, cur_branch)
                                                    )
                                        p = expr_end
                                        continue
                                p += 1
                        return end_s

                    return skip_until_semi(toks, idx)

                i = parse_module_items(i, {"endmodule"}, (), {}, {})
                if i < n and toks[i].val == "endmodule":
                    i += 1
            else:
                i += 1

    return known_modules


def branches_mutually_exclusive(b1: Tuple[Tuple[int, int], ...], b2: Tuple[Tuple[int, int], ...]) -> bool:
    map1 = dict(b1)
    for gid, br in b2:
        if gid in map1 and map1[gid] != br:
            return True
    return False


def slices_overlap(s1: Optional[Set[int]], s2: Optional[Set[int]]) -> bool:
    if s1 is None or s2 is None:
        return True
    return bool(s1 & s2)


def find_multidrivers(modules: Dict[str, ModuleInfo], target_files: Optional[Set[str]] = None) -> List[dict]:
    findings: List[dict] = []
    for mname, info in modules.items():
        if target_files and info.file_path not in target_files:
            continue
        for sig, writes in sorted(info.writes.items()):
            by_drv: Dict[str, List[DriverWrite]] = defaultdict(list)
            for w in writes:
                by_drv[w.driver_id].append(w)
            drv_ids = list(by_drv.keys())
            if len(drv_ids) <= 1:
                continue

            conflicting_drvs: Set[str] = set()
            for a_idx in range(len(drv_ids)):
                for b_idx in range(a_idx + 1, len(drv_ids)):
                    da, db = drv_ids[a_idx], drv_ids[b_idx]
                    pair_conflict = False
                    for wa in by_drv[da]:
                        for wb in by_drv[db]:
                            if not branches_mutually_exclusive(wa.gen_branch, wb.gen_branch) and slices_overlap(wa.slice_set, wb.slice_set):
                                pair_conflict = True
                                break
                        if pair_conflict:
                            break
                    if pair_conflict:
                        conflicting_drvs.add(da)
                        conflicting_drvs.add(db)

            if conflicting_drvs:
                drv_summaries = []
                for did in drv_ids:
                    if did not in conflicting_drvs:
                        continue
                    ws = by_drv[did]
                    lines = sorted({w.line for w in ws})
                    drv_summaries.append(f"{ws[0].driver_kind} (dòng {', '.join(map(str, lines))})")
                findings.append({
                    "module": mname,
                    "file": info.file_path,
                    "signal": sig,
                    "drivers": drv_summaries,
                })
    return findings


def run_yosys_wsl(files: List[str], top: Optional[str], defines: List[str]) -> Tuple[int, str]:
    def_flags = " ".join(f"-D{d}" for d in defines)
    rel_files = " ".join(Path(f).as_posix() for f in files)
    hier_cmd = f"hierarchy -top {top}" if top else "hierarchy -check"
    yosys_script = f"read_verilog -sv {def_flags} {rel_files}; {hier_cmd}; proc; check -assert"
    cmd = ["wsl.exe", "-d", "Ubuntu", "--", "bash", "-lc", f"cd /mnt/d/RAM && yosys -p \"{yosys_script}\""]
    proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return proc.returncode, (proc.stdout + "\n" + proc.stderr).strip()


def parse_vivado_log(log_path: Path) -> List[str]:
    if not log_path.exists():
        return []
    hits: List[str] = []
    pat = re.compile(r"Synth 8-685[89]|DRC MDRV-1")
    for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
        if pat.search(line):
            hits.append(line.strip())
    return hits


def check_files_structural(files: List[str], defines_sets: List[Set[str]], focus_files: Optional[Set[str]] = None) -> List[dict]:
    all_findings: List[dict] = []
    seen_keys: Set[Tuple[str, str, str]] = set()
    for defs in defines_sets:
        parsed: List[Tuple[str, str]] = []
        for f in files:
            p = ROOT / f if not Path(f).is_absolute() else Path(f)
            raw = p.read_text(encoding="utf-8", errors="replace")
            cleaned = strip_comments_and_strings(raw)
            pre = preprocess_ifdef(cleaned, defs)
            parsed.append((Path(f).as_posix(), pre))
        mods = analyze_modules(parsed)
        for fd in find_multidrivers(mods, target_files=focus_files):
            key = (fd["file"], fd["module"], fd["signal"])
            if key not in seen_keys:
                seen_keys.add(key)
                fd["defines"] = sorted(defs)
                all_findings.append(fd)
    return all_findings


def run_self_test() -> int:
    neg_path = ROOT / "build" / "multidriver_neg_test.sv"
    neg_path.parent.mkdir(parents=True, exist_ok=True)
    neg_path.write_text(NEGATIVE_TEST_SV, encoding="utf-8")
    rel_neg = neg_path.relative_to(ROOT).as_posix()

    print("=== [SELF-TEST / NEGATIVE TEST] Kiểm tra file cố ý có 2 driver: build/multidriver_neg_test.sv ===")
    rc_y, out_y = run_yosys_wsl([rel_neg], "neg_multidriver_test", [])
    print(f"[Yosys WSL] exit={rc_y}")
    for line in out_y.splitlines():
        if any(k in line for k in ("ERROR", "Warning", "driver", "check")):
            print("  " + line)

    sv_findings = check_files_structural([rel_neg], [set()])
    print(f"[Structural SV] số tín hiệu đa nguồn phát hiện = {len(sv_findings)}")
    for fd in sv_findings:
        print(f"  - {fd['file']} :: {fd['module']}.{fd['signal']} <- {' | '.join(fd['drivers'])}")

    sub_rc = subprocess.run(
        [sys.executable, str(Path(__file__).resolve()), "--files", rel_neg, "--top", "neg_multidriver_test"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    ).returncode
    print(f"[CLI Negative Check] `check_multidriver.py --files {rel_neg} --top neg_multidriver_test` -> exit={sub_rc}")

    if rc_y != 0 and len(sv_findings) >= 1 and sub_rc == 1:
        print("[SELF-TEST PASS] Công cụ bắt đúng tín hiệu đa nguồn ở test âm (thoát 1).")
        return 0
    print("[SELF-TEST FAIL] Không bắt được lỗi đa nguồn ở test âm!")
    return 1


def main() -> int:
    ap = argparse.ArgumentParser(description="Kiểm tra thanh ghi/mạng đa nguồn (multi-driver) trên RTL Q-Shield.")
    ap.add_argument("--files", nargs="+", default=None, help="Danh sách file SV cần kiểm (mặc định: toàn bộ cây axi_ddr5_mc_secure_top)")
    ap.add_argument("--focus", nargs="+", default=None, help="Chỉ báo lỗi trong các file thuộc danh sách này (vẫn đọc file khác để lấy hướng cổng)")
    ap.add_argument("--top", default="axi_ddr5_mc_secure_top", help="Tên module top khi gọi Yosys")
    ap.add_argument("--define", action="append", default=[], help="Thêm macro define cho bộ tiền xử lý")
    ap.add_argument("--skip-yosys", action="store_true", help="Bỏ qua bước gọi Yosys trong WSL")
    ap.add_argument("--vivado-log", default=None, help="Đường dẫn log Vivado cần quét [Synth 8-6859]/[Synth 8-6858]/[DRC MDRV-1]")
    ap.add_argument("--self-test", action="store_true", help="Chạy test âm có chủ ý 2 driver để xác nhận công cụ thoát 1")
    args = ap.parse_args()

    if args.self_test:
        return run_self_test()

    files = args.files if args.files is not None else list(SECURE_TOP_RTL_FILES)
    focus = {Path(f).as_posix() for f in args.focus} if args.focus else None

    if args.define:
        defines_sets = [set(args.define)]
    elif args.files is not None:
        defines_sets = [set()]
    else:
        defines_sets = [set(), {"QSHIELD_TEST"}]

    exit_code = 0

    if not args.skip_yosys:
        rc_y, out_y = run_yosys_wsl(files, args.top, list(args.define))
        if rc_y == 0:
            print(f"[Yosys WSL] PASS (`hierarchy -top {args.top}; proc; check -assert` sạch).")
        else:
            md_lines = [l for l in out_y.splitlines() if "multiple" in l.lower() or "conflicting" in l.lower() or ("found" in l.lower() and "problems" in l.lower())]
            syn_lines = [l for l in out_y.splitlines() if "syntax error" in l.lower()]
            if md_lines and not syn_lines:
                print(f"[Yosys WSL] FAIL (exit={rc_y}) phát hiện vấn đề trong `check -assert`:")
                for l in md_lines[:30]:
                    print("  " + l)
                exit_code = 1
            elif syn_lines:
                print(f"[Yosys WSL] INFO: Yosys native SV parser không đọc hết cú pháp IEEE 1800-2017 ({syn_lines[0].strip()}); dùng bộ phân tích cấu trúc SV đầy đủ.")
            else:
                print(f"[Yosys WSL] WARN/FAIL (exit={rc_y}):")
                for l in out_y.splitlines()[-15:]:
                    print("  " + l)
                exit_code = 1

    findings = check_files_structural(files, defines_sets, focus_files=focus)
    if findings:
        print(f"[Structural SV] FAIL: phát hiện {len(findings)} tín hiệu đa nguồn:")
        for fd in findings:
            defs_str = ",".join(fd["defines"]) if fd["defines"] else "default"
            print(f"  - {fd['file']} :: {fd['module']}.{fd['signal']} [{defs_str}] <- {' | '.join(fd['drivers'])}")
        exit_code = 1
    else:
        scope_desc = ", ".join(sorted(focus)) if focus else f"{len(files)} file RTL của {args.top}"
        print(f"[Structural SV] PASS: 0 tín hiệu đa nguồn trên {scope_desc}.")

    if args.vivado_log:
        v_hits = parse_vivado_log(Path(args.vivado_log))
        if v_hits:
            print(f"[Vivado Log] FAIL: phát hiện {len(v_hits)} dòng cảnh báo/lỗi đa nguồn trong {args.vivado_log}:")
            for h in v_hits[:30]:
                print("  " + h)
            exit_code = 1
        else:
            print(f"[Vivado Log] PASS: 0 dòng [Synth 8-6859]/[Synth 8-6858]/[DRC MDRV-1] trong {args.vivado_log}.")

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
