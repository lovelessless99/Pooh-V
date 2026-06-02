# Pooh-V Roadmap

## Completed

- **Phase 1** — RV64I + RV64M base instruction generator, SMT constraint solver, ELF flat binary
- **Phase 2** — RV64A / RV64F / RV64D / RV64C extensions, Scenario system, Co-simulation with Spike
- **Phase 3** — Coverage-guided generation, Thompson Sampling bandit, Servant REST API (6 endpoints)
- **Phase 4** — Vue3 dashboard, real-time SSE updates, Chart.js coverage/bandit charts, interactive controls

---

## TODO

### Phase 5: RVV Vector Extension

**Goal:** Add RISC-V Vector (RVV 1.0) instruction support to the generator.

**Scope:**
- `Core.Instruction` — add RVV instruction types (vsetvli, vle/vse, vadd, vmul, …)
- `Core.Encode` — encode V-extension instructions (variable-length element groups, LMUL, SEW)
- `Coverage.Types` — add vector coverage bins (element widths × operations × LMUL settings)
- `Generator.Types` — add `RV64V` to the `Extension` enum
- `Constraint.Library` — vector register constraints (v0–v31, alignment rules)
- `Scenario.Registry` — vector-specific scenarios (e.g. reduction, strided load/store)
- Tests — unit tests for encoding correctness, coverage classification

**Key challenge:** RVV instructions have a dynamic type system (vtype register controls element width and grouping at runtime) — the constraint solver needs to track vtype state across a sequence.
