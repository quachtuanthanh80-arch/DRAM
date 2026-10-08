# Q-Shield Security Resilience & Attack Emulation Evaluation Report

## 1. Summary Matrix

| Attack Profile | Category | Memory Accesses | Mitigations | Escaped Bit-Flips | Detection Rate | FPR | Attack Throughput Cut | Benign Slowdown |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Benign_Standard** | Benign Baseline | 5,000 | 1 | **0** | 100.0% | 0.020% | -0.0% | 1.00$\times$ |
| **Standard_RowHammer** | Alternating Double-Sided Hammer | 5,000 | 150 | **0** | 100.0% | 0.000% | -57.9% | 1.01$\times$ |
| **Blacksmith_MultiSided** | Frequency-Domain Non-Uniform Hammer | 5,000 | 61 | **0** | 100.0% | 0.000% | -57.9% | 1.01$\times$ |
| **RowPress_Prolonged** | Prolonged Activation Hammer | 5,000 | 419 | **0** | 100.0% | 0.000% | -57.9% | 1.01$\times$ |
| **Mixed_MultiTenant** | Multi-Tenant Resource Contention | 8,000 | 58 | **0** | 100.0% | 0.000% | -57.9% | 1.02$\times$ |

## 2. Threat Model Boundaries & Assumptions

- **Attacker Capabilities**: Unprivileged native instruction execution with arbitrary row targeting.
- **Hardware Protections**: Dual-hash counting guarantees zero false negatives; ATE dynamically prevents threshold evasion.
- **Non-Defended Vectors**: Physical bus probing, interposer sniffing, and cryogenic row-retention reading are outside controller scope.
