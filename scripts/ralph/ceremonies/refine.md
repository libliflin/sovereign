# Backlog Refinement Ceremony

You are running the **backlog refinement ceremony** for the Sovereign Platform.

## Your task

Read `prd/backlog.json` and assess every story that has `passes: false` for refinement issues.
Then write your findings to two output files.

### Step 1 — Read the backlog

```bash
cat prd/backlog.json
```

### Step 2 — Assess each unfinished story for these issues

For each story where `passes: false`, check:

1. **Vague description** — Is the description specific enough to implement without asking a question?
   A vague description says *what* but not *how*. Flag if a developer could not start work immediately.

2. **Missing or weak acceptance criteria** — Are all ACs verifiable (concrete pass/fail)? Phrases like
   "works correctly" or "is good" are not verifiable. Each AC must be a binary check.

3. **No testPlan** — The `testPlan` field must describe actual commands or verification steps, not just
   repeat the ACs. Flag if it only says "verify all acceptanceCriteria".

4. **Missing dependencies** — Does the story reference other stories implicitly that are not listed in
   `dependencies[]`? (e.g. a chart story that needs a bootstrap story to have run first)

5. **Title not action-oriented** — Titles must start with a verb or name a concrete deliverable.
   "ArgoCD things" is bad. "Helm chart: ArgoCD App-of-Apps with OIDC stub" is good.

6. **Too large (points > 3)** — Stories with `points: 5` must be split before they can be implemented.
   Stories with `points: 3` that still feel overly broad should be flagged as split candidates.

### Step 3 — Write prd/refinement-report.json

Write a JSON file at `prd/refinement-report.json` with this schema:

```json
{
  "generatedAt": "<ISO timestamp>",
  "storiesAssessed": <number>,
  "issuesFound": <number>,
  "findings": [
    {
      "storyId": "023",
      "issue": "Vague description — says 'set up Istio' without specifying which Istio profile, which version, or which components (pilot, ingressgateway, egressgateway).",
      "suggestion": "Specify: Istio version 1.21, minimal profile, with PeerAuthentication STRICT mTLS for all namespaces except kube-system, and an ingress gateway IngressClass named 'istio'."
    }
  ]
}
```

One finding object per issue found. A single story can have multiple finding objects.
If no issues are found for a story, omit it from findings entirely.

### Step 4 — Write prd/proposed-splits.json for stories with points > 3

For each story with `points: 5` (or any story with `points: 3` you believe is too broad):

Write `prd/proposed-splits.json` with this schema:

```json
{
  "generatedAt": "<ISO timestamp>",
  "proposedSplits": [
    {
      "originalStoryId": "016",
      "reason": "GitLab install has 3 distinct concerns: chart scaffolding, DB migration job, and runner registration.",
      "proposedStories": [
        {
          "suggestedId": "016a",
          "title": "Helm chart: GitLab core install with PostgreSQL sub-chart",
          "points": 3,
          "description": "...",
          "acceptanceCriteria": ["..."]
        },
        {
          "suggestedId": "016b",
          "title": "GitLab: runner registration and CI variable seeding",
          "points": 2,
          "description": "...",
          "acceptanceCriteria": ["..."]
        }
      ]
    }
  ]
}
```

If no stories need splitting, write `{ "generatedAt": "...", "proposedSplits": [] }`.

## Important constraints

- **Do NOT modify `prd/backlog.json` directly.** Write only to `prd/refinement-report.json` and
  `prd/proposed-splits.json`. A human reviews the proposals before applying them.
- Be specific in your `suggestion` field — give the exact text change that would fix the issue.
- Focus on stories that are genuinely unclear, not on making perfect stories even better.

## Output

After writing both files, print a summary table to stdout:

```
=== Backlog Refinement Report ===
Stories assessed : <N>
Issues found     : <N>
Split candidates : <N>

Issues by category:
  Vague description    : <N>
  Weak ACs             : <N>
  No testPlan          : <N>
  Missing dependencies : <N>
  Bad title            : <N>
  Too large            : <N>

Files written:
  prd/refinement-report.json
  prd/proposed-splits.json
```
