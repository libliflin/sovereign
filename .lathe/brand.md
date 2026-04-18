# Brand

## Identity

Terse, declarative, technically precise. Sovereign speaks with the confidence of a
platform that has already thought through the edge cases — and made hard choices. It
holds lines without softening them for accessibility. Confident about its scope, explicit
about its limits. Not a consultant's positioning statement — an engineer's spec sheet for
a platform that takes sovereignty seriously.

The name is a declaration. "Autarky" earns its own dictionary entry in the README
(pronunciation included) because this project believes the concept matters enough to teach
it. That word-selection instinct — reaching for the exact right word rather than the
comfortable approximation — runs through the whole codebase.

---

## How We Speak

**When we say no:** Name the invariant, say why it exists, offer no workaround.

> "This is not configurable — it is an invariant of the sovereign contract."
> — `contract/validate.py:106`

> "HA is not optional. It is baked in from the first commit."
> — `cluster/CLAUDE.md`

No apology, no "for now," no escape hatch. The refusal is the feature.

**When we fail:** Category in ALL CAPS, then the specific field, then what was given.

> `CONTRACT VALIDATION FAILED: cluster-values.yaml`  
> `  x AUTARKY VIOLATION: autarky.externalEgressBlocked must be true (got 'false').`
> — `contract/validate.py:119–126`

> `  x MISSING required field: network.networkPolicyEnforced`
> — `contract/validate.py:95`

One line per failure. Prefix `  x `. No stack trace surfaced unless asked for. The
operator should be able to act on the error without reading source.

**When we explain:** State the rule, then explain why the rule exists — because the why
is what makes it stick.

> "BSL blocked (OpenBao not Vault)" — `CLAUDE.md`

> "etcd quorum: 3 nodes tolerate 1 failure. 2 nodes lose quorum on any failure."
> — `README.md`

The sovereignty doc leads with: "This is stronger than open source" — and then explains
why. Not "our policy is X" but "here is the threat model that created X."

**When we onboard:** Forward-pointing at every step. Dry-run previews each intended
action. Successful operations always end with the next command.

> `==> Cluster ready. Context: kind-sovereign-test`  
> `==> Next step: platform/deploy.sh --cluster-values cluster-values.yaml`
> — `cluster/kind/bootstrap.sh:63,107`

> `==> Cluster 'sovereign-test' already exists — skipping creation`
> — `cluster/kind/bootstrap.sh:53`

Idempotent and narrated. The operator should never have to guess where they are in the
sequence.

**When we celebrate:** "Cluster ready." "CONTRACT VALID." Full stop, move on. No
exclamation points. No emoji. The fact speaks.

> `CONTRACT VALID: cluster-values.yaml` — `contract/validate.py:124`

---

## The Thing We'd Never Do

Bury the actionable detail under a generic error. "Validation failed" with no field
name is a trust violation — Morgan can't diagnose at 3am, Casey can't integrate into CI,
Sam can't verify the claim is machine-checked. Every error in the codebase names the
exact field and states the rule it violated (`contract/validate.py:95–106`). That
discipline is non-negotiable.

---

## Signals to Preserve

**Em dash as a beat.** Used to attach a short reason or consequence to a fact, not a
comma or parenthesis:
`"DRY RUN — no cluster will be created"`, `"already exists — skipping creation"`.
(`cluster/kind/bootstrap.sh:43,53`)

**Principle before option.** State the invariant first; only then introduce the escape
hatch if one exists. Never lead with the workaround.
(`docs/governance/sovereignty.md`: "No exceptions." — then the exception pathway, three
paragraphs later.)

**"Next step:" at the end of success.** Every successful terminal operation points
forward. The operator never has to wonder what to run next.
(`cluster/kind/bootstrap.sh:107`)

**ALL CAPS category label, lowercase detail.** Error headers are loud; the specific
information underneath is readable. `AUTARKY VIOLATION: field must be true (got 'false')`.
(`contract/validate.py:103`)
