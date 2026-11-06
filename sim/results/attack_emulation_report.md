# Q-Shield Attack Emulation Report (Python Architectural Model)

> Results come from a Python model, not from RTL simulation. Fidelity limits:
> - Python architectural model, not RTL simulation.
> - hash1/hash2 are not the RTL PXOR hash (rtl/core/pxor_hash_engine.sv).
> - Trace address mapping (BG=addr[17:16], bank=addr[15:14]) differs from rtl/frontend (BG=addr[8:6]^addr[20:18], bank=addr[17:16]).
> - Bit flips are modelled as victim rows reaching HC_FIRST neighbour activations without an intervening refresh.
> - Assumed HC_FIRST = 4800 activations; detection is N/A when a trace never reaches it.

## 1. Summary Matrix (Standardized Threat Vectors)

| Attack Profile | Category | Memory Accesses | Mitigations | Escaped Bit-Flips | Detection Rate | FPR | Attack Throughput Cut | Benign Slowdown |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Benign_Standard** | Benign Baseline | 5,000 | 1 | **0** | N/A | 0.020% | -0.0% | 1.00$\times$ |
| **Standard_RowHammer** | Alternating Double-Sided Hammer | 5,000 | 150 | **0** | N/A | 0.000% | -16.67% | 1.20$\times$ |
| **Blacksmith_MultiSided** | Frequency-Domain Non-Uniform Hammer | 5,000 | 61 | **0** | N/A | 0.000% | -7.52% | 1.08$\times$ |
| **RowPress_Prolonged** | Prolonged Activation Hammer | 5,000 | 419 | **0** | N/A | 0.000% | -35.84% | 1.56$\times$ |
| **Mixed_MultiTenant** | Multi-Tenant Resource Contention | 8,000 | 58 | **0** | N/A | 0.000% | -4.61% | 1.05$\times$ |
| **ZenHammer_DDR5** | DDR5 Physical Adjacency Hammer | 10,000 | 1,248 | **0** | N/A | 0.000% | -45.41% | 1.83$\times$ |
| **Crystalor_Hash_Collision** | Dual-Hash Collision Evasion | 10,000 | 300 | **0** | N/A | 0.000% | -16.67% | 1.20$\times$ |
| **Cross_Epoch_Split_Hammer** | Epoch Boundary Split & Half-Double | 10,000 | 150 | **0** | 100.0% | 0.000% | -9.09% | 1.10$\times$ |

## 2. Tier 1 Adversarial Address Fuzzing (1,000,000 Transactions)

- **Total Transactions**: 1,000,000
- **Rate Pacing Mitigations**: 5,743
- **Benign False Positive Rate**: **0.0000%**
- **Escaped Bit-Flips**: **0** (model)
- **Execution Speed**: 207,582.8 ops/sec (4.82s)

## 3. Threat Model Boundaries & Assumptions

- **Attacker Capabilities**: Unprivileged native instruction execution with arbitrary row targeting.
- **RTL status**: open RTL gaps found by tb/top/tb_security_attacks_vcd.sv (e.g. S8 epoch split, S10 threshold loosening, S11 dropped alerts) are not modelled here.
- **Non-Defended Vectors**: Physical bus probing, interposer sniffing, and cryogenic row-retention reading are outside controller scope.
