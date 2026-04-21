#!/usr/bin/env python3
import argparse
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


def iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def resolve_prompts(prompt_list: Path) -> list[Path]:
    prompts: list[Path] = []
    base = prompt_list.parent
    for raw in prompt_list.read_text().splitlines():
        line = raw.rstrip()
        if not line or line.startswith("#"):
            continue
        p = Path(line)
        if not p.is_absolute():
            p = base / p
        p = p.resolve()
        if not p.is_file():
            raise FileNotFoundError(f"Prompt file not found: {p}")
        prompts.append(p)
    if not prompts:
        raise ValueError("Prompt list contains no usable prompt files.")
    return prompts


def main() -> int:
    ap = argparse.ArgumentParser(
        prog="converge.py",
        description="Run a rotating agent loop with per-step handoff artifacts.",
        formatter_class=argparse.RawTextHelpFormatter,
        epilog=(
            "Prompt list rules:\n"
            "  - empty lines are ignored\n"
            "  - lines starting with # are ignored\n"
            "  - relative prompt paths are resolved from prompt-list directory\n\n"
            "Examples:\n"
            "  python3 scripts/converge.py --session-dir ./session --prompt-list ./prompts.txt --agent-cmd \"codex exec --dangerously-bypass-approvals-and-sandbox -\" --max-steps 6\n"
            "  python3 scripts/converge.py --session-dir ./session --prompt-list ./prompts.txt --agent-cmd \"claude -p --permission-mode bypassPermissions\"\n"
            "  python3 scripts/converge.py --session-dir ./session --prompt-list ./prompts.txt --agent-cmd \"cursor-agent -p --yolo --trust --approve-mcps\""
        ),
    )
    ap.add_argument("--session-dir", required=True, help="Session root for run artifacts.")
    ap.add_argument("--prompt-list", required=True, help="File with one prompt path per line.")
    ap.add_argument("--agent-cmd", required=True, help="Agent command, e.g. 'codex exec' or 'claude'.")
    ap.add_argument("--max-steps", type=int, default=10, help="Number of loop iterations (default: 10).")
    args = ap.parse_args()
    if args.max_steps < 1:
        print("--max-steps must be a positive integer.", file=sys.stderr)
        return 1

    session_dir = Path(args.session_dir).resolve()
    session_dir.mkdir(parents=True, exist_ok=True)
    prompt_list = Path(args.prompt_list).resolve()
    if not prompt_list.is_file():
        print(f"Prompt list not found: {prompt_list}", file=sys.stderr)
        return 1
    prompts = resolve_prompts(prompt_list)

    run_dir = session_dir / "run"
    loop_dir = run_dir / "loop"
    loop_dir.mkdir(parents=True, exist_ok=True)
    loop_log = loop_dir / "loop.log"
    loop_log.touch(exist_ok=True)

    print("Starting agent loop")
    print(f"session_dir={session_dir}")
    print(f"prompt_count={len(prompts)}")
    print(f"max_steps={args.max_steps}")
    print(f"agent_cmd={args.agent_cmd}")

    for step in range(1, args.max_steps + 1):
        prompt = prompts[(step - 1) % len(prompts)]
        step_dir = run_dir / f"s{step:03d}"
        step_dir.mkdir(parents=True, exist_ok=True)

        prev_handoff = run_dir / f"s{step - 1:03d}" / "handoff.md"
        input_handoff = prev_handoff if step > 1 and prev_handoff.is_file() else None
        output_handoff = step_dir / "handoff.md"
        effective = step_dir / "effective_prompt.md"
        stdout_log = step_dir / "stdout.log"
        stderr_log = step_dir / "stderr.log"
        exit_file = step_dir / "exit_code.txt"

        output_handoff.write_text("")
        stdout_log.write_text("")
        stderr_log.write_text("")
        header = [
            "# Runtime Protocol",
            "",
            f"- step: {step}",
            f"- input_handoff: {input_handoff}" if input_handoff else "- input_handoff: (none)",
            "- read input handoff as latest context." if input_handoff else "- no previous handoff exists for this step.",
            f"- output_handoff: {output_handoff}",
            "- write next handoff content to output_handoff.",
            "- do not modify files outside the task scope.",
            "",
            "# Role Prompt",
            "",
        ]
        effective.write_text("\n".join(header) + prompt.read_text())

        start_epoch = int(time.time())
        start_iso = iso_now()
        print(f"[step {step}] start prompt={prompt.name} time={start_iso}")
        with stdout_log.open("w") as out, stderr_log.open("w") as err:
            proc = subprocess.run(args.agent_cmd, shell=True, text=True, stdin=effective.open("r"), stdout=out, stderr=err)
        code = proc.returncode
        exit_file.write_text(f"{code}\n")

        end_iso = iso_now()
        elapsed = int(time.time()) - start_epoch
        print(f"[step {step}] done exit={code} elapsed={elapsed}s")
        with loop_log.open("a") as lf:
            lf.write(f"{end_iso} step={step} prompt={prompt} exit={code} elapsed_s={elapsed}\n")

    print(f"Loop finished after {args.max_steps} steps.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
