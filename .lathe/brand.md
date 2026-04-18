# Brand

## Identity

Declarative, conviction-first, no softening language. The project states what is true and what is required — it does not suggest, recommend, or persuade. Precision serves the mission (sovereignty as a political guarantee, not a marketing claim). When the project has a principle, it names it, defines it exactly, and writes code that enforces it.

Evidence: README.md:3 opens with "Clone, configure, run." — promise, not feature list. `contract/validate.py:104-106` names violations explicitly: `"AUTARKY VIOLATION: {field} must be true... This is not configurable — it is an invariant of the sovereign contract."` `docs/governance/scope.md:101-103` does not say "we prefer self-hosted" — it says "You deploy it. You operate it. You are responsible for it."

---

## How We Speak

**When we say no:** Short declarative sentence + technical reason. No apology. `README.md:198`: "**AWS free tier is not viable.** t2.micro/t3.micro (1 GB RAM) cannot run a k3s server node with embedded etcd." The refusal and the reason land in the same breath. `docs/governance/scope.md:91`: "This is a **BLOCKER**. Find the self-hosted alternative."

**When we fail:** Named violations, machine-readable format, no paragraph of context. `ha-gate.sh:129,132`: `FAIL:${chart_name}:replicaCount missing from values.yaml` and `FAIL:${chart_name}:replicaCount < 2`. `contract/validate.py:120,125`: `CONTRACT VALIDATION FAILED: {path}` / `x {error}` / `This cluster does not satisfy the sovereign contract.` Failure has a name and a specific location — not a vague failure.

**When we explain:** Define the term exactly, enumerate the failure modes, then stop. `docs/governance/sovereignty.md:3`: "Sovereign means the platform is free from any single vendor's ability to change terms, revoke access, alter the roadmap, or charge for continued use." Four specific failure modes. Not "free from vendor lock-in."

**When we onboard a new user:** Hand them the next command inline, immediately after the current command succeeds. `cluster/kind/bootstrap.sh:107-111` — after bootstrap completes, the script prints `Smoke test: helm install ...` and `Tear down: kind delete cluster ...`. The happy-path journey is self-contained — no archaeology required for the next step.

**When we celebrate:** We don't. `contract/validate.py:128`: `CONTRACT VALID: {path}`. No exclamation mark, no "great job," no flourish. Success is a fact, not an event. `ha-gate.sh:184`: `PASS:${chart_name}`. Colon, name, done.

---

## The Thing We'd Never Do

Hedge a hard rule. When something is required, the script refuses — it does not warn. `cluster/CLAUDE.md:1-2`: "bootstrap.sh MUST refuse to proceed with fewer than 3 nodes... HA is not optional. It is baked in from the first commit." The distinction between MUST and SHOULD is load-bearing here. We would never write: "we recommend at least 3 nodes." The code enforces it; the docs state it as fact. Softening a constitutional constraint would be the single most off-brand thing this project could do.

---

## Signals to Preserve

1. **Colon-delimited structured output for gates.** `FAIL:chart:reason`, `PASS:chart`, `CONTRACT VALID: path`, `CONTRACT VALIDATION FAILED: path`. Machine-readable, parseable, consistent. Do not change gate output to prose sentences.

2. **Em-dash for inline sub-clarification in commit messages and docs.** `feat: add network-policies chart — enforce externalEgressBlocked at workload layer`. The em-dash signals "the headline is complete; this is the why." Use it exactly that way — not for elaboration, for the enforcement target.

3. **Named violations, not generic errors.** `AUTARKY VIOLATION`, `CONTRACT VALIDATION FAILED`, `BLOCKER`. When a constraint is broken, name the constraint that was broken. Generic error messages dilute this signal — the project has constitutional categories; the output should reflect them.
