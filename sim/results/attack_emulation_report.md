# Q-Shield Security Resilience & Attack Emulation Evaluation Report

## 1. Summary Matrix (Standardized Threat Vectors)

| Attack Profile | Category | Memory Accesses | Mitigations | Escaped Bit-Flips | Detection Rate | FPR | Attack Throughput Cut | Benign Slowdown |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Benign_Standard** | Benign Baseline | 5,000 | 1 | **0** | 100.0% | 0.020% | -0.0% | 1.00$\times$ |
| **Standard_RowHammer** | Alternating Double-Sided Hammer | 5,000 | 150 | **0** | 100.0% | 0.000% | -57.9% | 1.01$\times$ |
| **Blacksmith_MultiSided** | Frequency-Domain Non-Uniform Hammer | 5,000 | 61 | **0** | 100.0% | 0.000% | -57.9% | 1.01$\times$ |
| **RowPress_Prolonged** | Prolonged Activation Hammer | 5,000 | 419 | **0** | 100.0% | 0.000% | -57.9% | 1.01$\times$ |
| **Mixed_MultiTenant** | Multi-Tenant Resource Contention | 8,000 | 58 | **0** | 100.0% | 0.000% | -57.9% | 1.02$\times$ |
| **ZenHammer_DDR5** | DDR5 Physical Adjacency Hammer | 10,000 | 1,248 | **0** | 100.0% | 0.000% | -57.9% | 1.01$\times$ |
| **Crystalor_Hash_Collision** | Dual-Hash Collision Evasion | 10,000 | 300 | **0** | 100.0% | 0.000% | -57.9% | 1.01$\times$ |
| **Cross_Epoch_Split_Hammer** | Epoch Boundary Split & Half-Double | 10,000 | 150 | **0** | 100.0% | 0.000% | -57.9% | 1.01$\times$ |

## 2. Tier 1 Adversarial Address Fuzzing (1,000,000 Transactions)

- **Total Transactions**: 1,000,000
- **Rate Pacing Mitigations**: 5,743
- **Benign False Positive Rate**: **0.0000%** (Target: $\le 0.02\%$)
- **Escaped Bit-Flips**: **0** (Complete Protection)
- **Execution Speed**: 276,677.4 ops/sec (3.61s)

## 3. Threat Model Boundaries & Assumptions

- **Attacker Capabilities**: Unprivileged native instruction execution with arbitrary row targeting.
- **Hardware Protections**: Dual-hash counting guarantees zero false negatives; ATE dynamically prevents threshold evasion.
- **Non-Defended Vectors**: Physical bus probing, interposer sniffing, and cryogenic row-retention reading are outside controller scope.
