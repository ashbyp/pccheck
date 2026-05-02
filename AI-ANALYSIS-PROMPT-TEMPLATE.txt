# AI Analysis Prompt Template (For `PCDiag_*.zip`)

Use this in a fresh AI session after uploading a `PCDiag_*.zip` file.

---

I uploaded a Windows diagnostics bundle (`PCDiag_*.zip`).

Please analyze it and produce a **root-cause-focused performance diagnosis**.

## Goals

1. Rank likely root causes by confidence (high/medium/low).
2. Cite exact evidence from the bundle:
- file path
- event IDs
- timestamps
- process/service names
3. Distinguish **primary causes** vs **secondary symptoms**.
4. Provide a prioritized remediation plan:
- Safe actions first
- Advanced/riskier actions second
5. Provide a verification plan:
- What to measure after each fix
- What “improved” vs “not improved” looks like

## Output format

1. **Executive Summary** (5-10 lines)
2. **Ranked Findings** (table: cause, confidence, evidence, impact)
3. **Evidence Log** (key events with timestamp + source file)
4. **Action Plan** (ordered, with expected impact and risk)
5. **Validation Checklist** (what to re-run and compare)
6. **Open Questions** (only if blocking)

## Analysis rules

- Do not give generic advice without evidence.
- If uncertain, say exactly why.
- Prefer conclusions supported by multiple signals (events + snapshots + crash artifacts).
- Call out contradictory signals explicitly.

## User context (fill this in before sending)

- Symptoms:
- When it happens:
- How often:
- Recent changes (drivers/updates/new software/peripherals):
- External devices connected during issue:
- What I already tried:

## Optional focus flags (remove any that don't apply)

- Focus on storage/I/O
- Focus on memory pressure
- Focus on app hangs/crashes
- Focus on startup/background services
- Focus on network/Wi-Fi instability
- Focus on GPU/driver issues

---

Also include a short section: **“If I can only do 3 things now”** with the top 3 highest-value actions.

