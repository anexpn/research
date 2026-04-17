This summary outlines the **Converge** pattern: a high-integrity, multi-agent loop designed to replace a single agent with a verifiable, self-correcting system.

---

## 1. The Core Philosophy
The **Converge** skill moves a project from an "unsolved" state to a "verified success" state by balancing three distinct biases: **Implementation**, **Critique**, and **Arbitration**. It relies on deterministic evidence (tests) rather than linguistic "vibes."

## 2. The Personas (The Sentinels)
* **The Conductor (Orchestrator):** The top-level manager. It initializes the session, manages the round-based file structure, assembles the context for each sub-agent, and handles the "Fail Fast" logic.
* **The Builder (Agent A):** High-velocity implementation. Its goal is to reach the success criteria by the shortest path. It must provide execution logs/test results as evidence of its progress.
* **The Inspector (Agent B):** The standards-bearer. Biased toward code quality and style, it uses project-level reference files (good/bad cases) to find deviations. It must provide evidence for every critique.
* **The Judge (Agent C):** The resolver. It evaluates the Builder’s results against the Inspector’s critiques. It can overrule the Inspector if the critique is invalid or pedantic. It distills the "Delta" (what to do next) for the next round.

## 3. The File System Protocol
All communication happens through the file system to ensure statelessness and auditability.

### Project-Level (Immutable/Global)
Defined in `AGENTS.md`, these are the "North Star" documents:
* **`.agents/standards/`**: Contains `quality_gate.md` and directories for `reference_good/` and `reference_bad/` code samples.

### Session-Level (Round-Based History)
The Conductor creates a unique session folder for every task:
* **`goal.md`**: The immutable objective and success criteria.
* **`round_N/`**: Each iteration is preserved:
    * **`builder_report.md`**: Status, changes (diffs), and raw execution/test logs.
    * **`inspector_review.md`**: List of violations with evidence tied to reference files.
    * **`judge_resolution.md`**: The final verdict. Contains `status: [CONTINUE|COMPLETE]` and the `delta_instructions` for the next Builder.

## 4. Operational Guardrails
* **Fresh Context:** Every agent starts "fresh." The Conductor provides only the `goal.md` and the *immediately preceding* `judge_resolution.md`. This prevents context bloat and "AI amnesia."
* **Fail Fast:** If any agent detects a fundamental blocker (e.g., environment failure, missing dependency), it flags a `blocker_detected` status. The Conductor terminates the loop immediately to save tokens and time.
* **Evidence-Based Opposition:** The Judge cannot simply ignore the Inspector; it must write out the logic/evidence for why a critique is being overruled.
* **The "Converge" Limit:** The Conductor tracks the round count. If the loop does not converge within $X$ rounds, it triggers a "Graceful Failure" for human intervention.

## 5. Execution Workflow
1.  **Conductor** creates `round_1`.
2.  **Builder** implements and runs verification (unit/integration tests). Writes report.
3.  **Inspector** reviews Builder’s work against standards. Writes review.
4.  **Judge** compares report vs. review. 
    * If goals met: **End loop.**
    * If not: **Judge** writes the "Delta" (instructions for next Architect).
5.  **Conductor** starts `round_2` with the Judge's Delta.

---

This design ensures that "Done" actually means "Verified," and that code quality isn't sacrificed for speed, nor speed for pedantry. Use this summary as the **System Specification** for your Orchestrator agent.
