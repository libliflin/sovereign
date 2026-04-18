# Brand

**Systems-engineer voice — terse, declarative, structured.** The project speaks the same way to
operators, contributors, and itself. Errors are formatted for parsing; success messages are a
single line. The project is confident about its scope and states its limits as invariants, not
preferences. There's no softening layer.

---

## Identity

Sovereign speaks like someone who already knows what they think and wants to move on.
One-sentence README promise, no feature list: "A fully self-hosted, zero-trust, high-availability
Kubernetes development platform. Clone, configure, run." (README.md line 3). When it defines a
term, it defines it with a pronunciation guide: `**Autarky** /ˈɔːtɑːki/` (README.md line 7) —
the project assumes you'll look things up or already know them, and doesn't condescend either way.

Refusals are categorical, not contextual. The contract validator says: "This is not
configurable — it is an invariant of the sovereign contract." (contract/validate.py line 105).
CLAUDE.md says: "No deferrals, no 'known issues.'" The CONTRIBUTING.md says: "Fix the specific
failure; don't work around it." These are not community norms — they're the same register the
project uses in its own scripts.

---

## How We Speak

**When we say no**, we name the invariant and stop: `AUTARKY VIOLATION: autarky.externalEgressBlocked
must be true (got 'false'). This is not configurable — it is an invariant of the sovereign
contract.` (contract/validate.py lines 104–106). Not "it looks like this may not meet our
requirements." The violation is named; the reason follows in a second sentence if it helps;
negotiation is not implied.

**When we fail**, we lead with the label and the specific reason:
`FAIL:${chart_name}:no PodDisruptionBudget in rendered templates` (ha-gate.sh line 209);
`BOOTSTRAP NOT IMPLEMENTED: VPS provisioning is not yet available.` followed immediately by
two working alternatives (bootstrap/bootstrap.sh lines 12–20). The error is the whole message.
There's no stack trace buried under a preamble — the actionable detail is the first thing you read.

**When we explain**, we use the enforcement target. Commit messages follow `type: description —
enforcement target` (CONTRIBUTING.md line 87). Examples from git log:
`fix: ha-gate SKIP for empty-rendering stub charts — avoid false HA failures`;
`fix: replica check — DaemonSet + Deployment(replicas absent) no longer masks HA gap`.
The em-dash is not decoration — it names *what the change enforces*, which is the project's
primary unit of meaning.

**When we onboard a new user**, we give them the gates before anything else:
"Run the gates below before you push." (CONTRIBUTING.md line 8). The gates are copy-pasteable
commands, not principles. A new contributor is a gate-runner first, a collaborator second.
Success looks like: `PASS:chart-name`.

**When we give an institutional warning**, we speak from memory: "When this happens again —
and it will — the response is..." (sovereignty.md line 85, on the Vault→OpenBao migration).
Not "if this ever happens." Not "should this situation arise." The project has been burned before
and speaks accordingly.

---

## The Thing We'd Never Do

We'd never soften a refusal. When the contract is violated, the output is
`CONTRACT VALIDATION FAILED` — all caps, label-first (contract/validate.py line 121). When
bootstrap.sh is a stub, it exits with `BOOTSTRAP NOT IMPLEMENTED`, not "this feature isn't ready
yet" or "coming soon." The scope doc names what Sovereign is not in a section called
"Sovereign Is Not" — eight bullet points, no hedging, no "however" (docs/governance/scope.md).
The project does not cushion a no to make it easier to ignore.

---

## Signals to Preserve

- **Commit message rhythm**: `type: description — enforcement target`. The em-dash and the enforcement
  clause are load-bearing — they make every commit legible as a claim about what was wrong and what
  invariant it now upholds.

- **Error message structure**: `LABEL:scope:reason` (machine-parseable) or `ALL CAPS LABEL: human
  sentence` followed immediately by the fix or alternative. Never lead with context; lead with
  the failure and what to do about it.

- **Invariant language**: phrases like "this is not configurable", "non-negotiable",
  "no exceptions" appear in scripts, docs, and CLAUDE.md alike. When the project uses these
  words, it means them the same way everywhere. Don't soften them in new copy.
