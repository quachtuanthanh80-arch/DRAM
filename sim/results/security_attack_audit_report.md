# Q-Shield Security Audit Report

- Commit: `916b881bb4515185778db15720309957f3380818`
- Overall verdict: **OPEN_VULNERABILITIES**

| Tier | Abstraction | Status | Evidence |
| :--- | :--- | :---: | :--- |
| 1 | Python architectural model | RAN | 0 escaped flips in model; 7/8 traces never reach HC_FIRST undefended |
| 2 | RTL (Icarus Verilog) | PASS_WITH_OPEN_GAPS | 30 checks, 0 failed, 12 open-gap checks |
| 3 | Formal (SymbiYosys) | NOT_RUN | 12 jobs |

## Open vulnerabilities found by the RTL red-team suite

- **S10**: V0 effective SDC threshold 514 after hammering (configured 3)
- **S8**: V2 cumulative hammering across epochs must be mitigated (throttle +0, REF 3)
- **S14**: V4 RowPress alert raised with curve 2 (equality comparison against falling threshold)
- **R18**: V8 high-QoS read completed in 217 cycles (bound 2x baseline = 46)
- **R9**: V10 read-back data equals written (wrote deadbeefcafebabe, read aaaa000000000700)
- **R17**: V13 distance-2 victim refresh issued (20 REF total)
- **S11**: V14 every hot aggressor got targeted refresh (15/16)
- **R18**: V16 high-QoS read served in 183 cycles (bound 2x baseline = 46)
- **S18**: V17 decoy produced real DRAM activations (0 ACT)
- **S16**: V6 same logical row maps to same physical row (first 0xd38c, again 0x190f9)
- **S16**: V15 axi_ddr5_mc_top has no DFI data bus; scrambled/encrypted DRAM data is not observable
- **R9**: V15 read-back with scrambling enabled equals written data
