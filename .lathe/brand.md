# Brand

## Identity

Workbench-grade precision: tells you exactly what failed and exactly why the invariant matters, with no softening and no stack trace dumps. The project has a vocabulary it insists on — autarky, sovereignty, zero trust — and uses it consistently and without apology. It refuses things in the declarative voice: *will refuse*, *is not viable*, *is not configurable*. Not academic, not casual. The voice of an engineer who won't ship around a problem.

---

## How We Speak

**When we say no:**
Hard declarative, no hedging. `"bootstrap.sh will refuse to proceed with fewer than 3 nodes or an even node count."` Not "an error may occur." Refuses. `"AWS free tier is not viable."` Not "may be insufficient for larger workloads." Not viable.
(README.md lines 76–77, 198)

**When we fail:**
Machine-readable, colon-delimited, exact. `FAIL:${chart_name}:replicaCount missing from values.yaml`. Chart name, rule name — no prose, no stack trace, nothing to parse before you get to the actionable part.
(ha-gate.sh lines 54–64)

**When we enforce an invariant:**
Name the violation class in capitals, state the invariant, close the door. `"AUTARKY VIOLATION: {field} must be true (got {value!r}). This is not configurable — it is an invariant of the sovereign contract."`
(contract/validate.py lines 103–106)

**When we explain a decision:**
One sentence, inline, explains the *why* not the *what*. `"# Skip if a release already exists (healthy or not) — surgeon fixes broken releases, operator doesn't retry them. This keeps the operator pass fast."` The comment earns its line count.
(platform/deploy.sh lines 78–79)

**When we succeed:**
One line, no ceremony. `CONTRACT VALID: {values_path}`. `PASS:${chart_name}`. `Cluster ready. Context: ${KUBE_CONTEXT}`. Done.
(contract/validate.py line 122; ha-gate.sh line 101; cluster/kind/bootstrap.sh line 63)

---

## The Thing We'd Never Do

Retire a gate with a quiet deletion. Every retired gate in `prd/constitution.json` gets a named post-mortem: what it was checking, why it stopped being worth the slot, what replaced it. `"A gate that never fires and measures presence rather than value is not protecting an invariant — it is occupying a slot."` The project is willing to be wrong in public and explain why it changed its mind. It would never quietly drop a constraint or silently relax an invariant. Visibility into the reasoning is load-bearing.
(prd/constitution.json `_retired` entries for G2, G5)

---

## Signals to Preserve

- **Lowercase, action-first commit messages.** `docs: align README`, `backstage fixes`, `lathe: cycle 43`. No narrative, no emoji, no present-tense prose.
- **SCREAMING_SNAKE for gate and contract verdicts.** `AUTARKY VIOLATION`, `CONTRACT VALID`, `G1 PASS`, `G6 FAIL`. These are verdicts, not log lines — their case signals that.
- **`will refuse` not `may fail`.** The platform enforces invariants; it does not emit warnings that operators can ignore. When a constraint is hard, the language is hard.
