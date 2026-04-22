#!/usr/bin/env python3
import argparse
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


def iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sanitize_tmux_label(text: str, fallback: str, max_len: int) -> str:
    safe = re.sub(r"[^A-Za-z0-9._-]+", "-", text.strip())
    safe = re.sub(r"-{2,}", "-", safe).strip("-")
    safe = safe[:max_len]
    return safe or fallback


def build_tmux_session_name(provided: str | None) -> str:
    if provided:
        return provided
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    return f"converge-{stamp}-{os.getpid()}"


def build_tmux_window_name(step: int, prompt: Path) -> str:
    suffix = sanitize_tmux_label(prompt.stem, "step", 24)
    return f"s{step:03d}-{suffix}"


def shell_escape_arg(text: str) -> str:
    escaped = re.sub(r"([^A-Za-z0-9_\-.,:+/@\n])", r"\\\1", text)
    return escaped.replace("\n", "'\n'")


def build_tmux_step_command(
    payload: str,
    *,
    agent_cmd: str,
    stdout_log: Path | None = None,
    stderr_log: Path | None = None,
) -> str:
    q = shlex.quote
    command = f"printf '%s' {q(payload)} | bash -c {q(agent_cmd)}"
    if stdout_log is not None and stderr_log is not None:
        command += f" > >(tee {q(str(stdout_log))}) 2> >(tee {q(str(stderr_log))} >&2)"
    return f"set -o pipefail; {command}"


def wait_for_tmux_window(session_name: str, window_name: str) -> int:
    target = f"{session_name}:{window_name}"
    while True:
        proc = subprocess.run(
            ["tmux", "list-panes", "-t", target, "-F", "#{pane_dead}"],
            check=False,
            capture_output=True,
            text=True,
        )
        if proc.returncode == 0 and proc.stdout.strip() == "1":
            break
        time.sleep(0.1)

    status = subprocess.run(
        ["tmux", "display-message", "-p", "-t", target, "#{pane_dead_status}"],
        check=True,
        capture_output=True,
        text=True,
    )
    raw = status.stdout.strip()
    return int(raw or "1")


def configure_tmux_window(session_name: str, window_name: str) -> None:
    target = f"{session_name}:{window_name}"
    subprocess.run(["tmux", "set-option", "-t", target, "remain-on-exit", "on"], check=True)
    subprocess.run(["tmux", "set-option", "-t", target, "automatic-rename", "off"], check=True)


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


def build_effective_prompt(
    step: int,
    *,
    agent_cmd: str,
    prompt: Path,
    input_handoff: Path | None = None,
    output_handoff: Path | None = None,
) -> str:
    header = [
        "# Runtime Protocol",
        "",
        f"- step: {step}",
        f"- agent_cmd: {agent_cmd}",
    ]
    if output_handoff is not None:
        header.extend(
            [
                f"- input_handoff: {input_handoff}" if input_handoff else "- input_handoff: (none)",
                "- read input handoff as latest context."
                if input_handoff
                else "- no previous handoff exists for this step.",
                f"- output_handoff: {output_handoff}",
                "- write next handoff content to output_handoff.",
            ]
        )
    header.extend(
        [
            "- do not modify files outside the task scope.",
            "",
            "# Role Prompt",
            "",
        ]
    )
    return "\n".join(header) + prompt.read_text()


def main() -> int:
    ap = argparse.ArgumentParser(
        prog="converge.py",
        description="Run a rotating agent loop with optional session artifacts and handoff.",
        formatter_class=argparse.RawTextHelpFormatter,
        epilog=(
            "Prompt list rules:\n"
            "  - empty lines are ignored\n"
            "  - lines starting with # are ignored\n"
            "  - relative prompt paths are resolved from prompt-list directory\n\n"
            "Examples:\n"
            "  python3 scripts/converge.py --prompt-list ./prompts.txt --agent-cmd \"codex exec --dangerously-bypass-approvals-and-sandbox -\" --max-steps 2\n"
            "  python3 scripts/converge.py --session-dir ./session --prompt-list ./prompts.txt --agent-cmd \"claude -p --permission-mode bypassPermissions\" --no-handoff\n"
            "  python3 scripts/converge.py --session-dir ./session --prompt-list ./prompts.txt --agent-cmd \"cursor-agent -p --yolo --trust --approve-mcps\" --handoff"
        ),
    )
    ap.add_argument("--session-dir", help="Optional session root for run artifacts.")
    ap.add_argument("--prompt-list", required=True, help="File with one prompt path per line.")
    ap.add_argument(
        "--agent-cmd",
        action="append",
        required=True,
        help="Agent command, e.g. 'codex exec' or 'claude'. Repeat to rotate commands by step.",
    )
    ap.add_argument("--max-steps", type=int, default=10, help="Number of loop iterations (default: 10).")
    ap.add_argument("--tmux", action="store_true", help="Run each step in a tmux window for live observability.")
    ap.add_argument("--tmux-session-name", help="Optional tmux session name override.")
    handoff = ap.add_mutually_exclusive_group()
    handoff.add_argument("--handoff", dest="handoff", action="store_true", help="Force handoff artifacts on. Requires --session-dir.")
    handoff.add_argument("--no-handoff", dest="handoff", action="store_false", help="Disable handoff artifacts.")
    ap.set_defaults(handoff=None)
    args = ap.parse_args()
    if args.max_steps < 1:
        print("--max-steps must be a positive integer.", file=sys.stderr)
        return 1

    session_dir: Path | None = None
    if args.session_dir:
        session_dir = Path(args.session_dir).resolve()
        session_dir.mkdir(parents=True, exist_ok=True)
    if args.handoff and session_dir is None:
        print("--handoff requires --session-dir.", file=sys.stderr)
        return 1
    prompt_list = Path(args.prompt_list).resolve()
    if not prompt_list.is_file():
        print(f"Prompt list not found: {prompt_list}", file=sys.stderr)
        return 1
    prompts = resolve_prompts(prompt_list)
    agent_cmds: list[str] = args.agent_cmd
    handoff_enabled = args.handoff if args.handoff is not None else session_dir is not None

    run_dir: Path | None = None
    loop_log: Path | None = None
    if session_dir is not None:
        run_dir = session_dir / "run"
        loop_dir = run_dir / "loop"
        loop_dir.mkdir(parents=True, exist_ok=True)
        loop_log = loop_dir / "loop.log"
        loop_log.touch(exist_ok=True)

    tmux_session_name: str | None = None
    tmux_created = False
    if args.tmux:
        if shutil.which("tmux") is None:
            print("--tmux requires tmux on PATH.", file=sys.stderr)
            return 1
        tmux_session_name = build_tmux_session_name(args.tmux_session_name)
        has_session = subprocess.run(
            ["tmux", "has-session", "-t", tmux_session_name],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if has_session.returncode == 0:
            print(f"tmux session already exists: {tmux_session_name}", file=sys.stderr)
            return 1

    print("Starting agent loop")
    if session_dir is not None:
        print(f"session_dir={session_dir}")
    print(f"prompt_count={len(prompts)}")
    print(f"max_steps={args.max_steps}")
    if len(agent_cmds) == 1:
        print(f"agent_cmd={agent_cmds[0]}")
    else:
        print(f"agent_cmd_count={len(agent_cmds)}")
    if tmux_session_name:
        print(f"tmux_session={tmux_session_name}")
        print(f"tmux_attach_cmd=tmux attach -t {shell_escape_arg(tmux_session_name)}")

    for step in range(1, args.max_steps + 1):
        prompt = prompts[(step - 1) % len(prompts)]
        agent_cmd = agent_cmds[(step - 1) % len(agent_cmds)]
        input_handoff: Path | None = None
        output_handoff: Path | None = None
        effective = stdout_log = stderr_log = None
        step_dir: Path | None = None
        if session_dir is not None and run_dir is not None:
            step_dir = run_dir / f"s{step:03d}"
            step_dir.mkdir(parents=True, exist_ok=True)
            stdout_log = step_dir / "stdout.log"
            stderr_log = step_dir / "stderr.log"
            stdout_log.write_text("")
            stderr_log.write_text("")
            if handoff_enabled:
                prev_handoff = run_dir / f"s{step - 1:03d}" / "handoff.md"
                input_handoff = prev_handoff if step > 1 and prev_handoff.is_file() else None
                output_handoff = step_dir / "handoff.md"
                output_handoff.write_text("")
            effective = step_dir / "effective_prompt.md"
            effective.write_text(
                build_effective_prompt(
                    step,
                    agent_cmd=agent_cmd,
                    prompt=prompt,
                    input_handoff=input_handoff,
                    output_handoff=output_handoff,
                )
            )

        start_epoch = int(time.time())
        start_iso = iso_now()
        print(f"[step {step}] start prompt={prompt.name} time={start_iso}")
        if tmux_session_name:
            payload = build_effective_prompt(
                step,
                agent_cmd=agent_cmd,
                prompt=prompt,
                input_handoff=input_handoff,
                output_handoff=output_handoff,
            )
            window_name = build_tmux_window_name(step, prompt)
            tmux_cmd = build_tmux_step_command(
                payload,
                agent_cmd=agent_cmd,
                stdout_log=stdout_log,
                stderr_log=stderr_log,
            )
            if not tmux_created:
                subprocess.run(
                    ["tmux", "new-session", "-d", "-s", tmux_session_name, "-n", window_name, "bash", "-c", tmux_cmd],
                    check=True,
                )
                configure_tmux_window(tmux_session_name, window_name)
                tmux_created = True
            else:
                subprocess.run(
                    ["tmux", "new-window", "-d", "-t", tmux_session_name, "-n", window_name, "bash", "-c", tmux_cmd],
                    check=True,
                )
                configure_tmux_window(tmux_session_name, window_name)
            code = wait_for_tmux_window(tmux_session_name, window_name)
            if step_dir is not None:
                (step_dir / "exit_code.txt").write_text(f"{code}\n")
        elif session_dir is not None:
            assert effective is not None
            assert stdout_log is not None
            assert stderr_log is not None
            with effective.open("r") as input_stream, stdout_log.open("w") as out, stderr_log.open("w") as err:
                proc = subprocess.run(["bash", "-c", agent_cmd], text=True, stdin=input_stream, stdout=out, stderr=err)
            code = proc.returncode
            (step_dir / "exit_code.txt").write_text(f"{code}\n")
        else:
            proc = subprocess.run(
                ["bash", "-c", agent_cmd],
                text=True,
                input=build_effective_prompt(step, agent_cmd=agent_cmd, prompt=prompt),
            )
            code = proc.returncode

        end_iso = iso_now()
        elapsed = int(time.time()) - start_epoch
        print(f"[step {step}] done exit={code} elapsed={elapsed}s")
        if loop_log is not None:
            with loop_log.open("a") as lf:
                lf.write(
                    f"{end_iso} step={step} prompt={prompt} agent_cmd={shlex.quote(agent_cmd)} exit={code} elapsed_s={elapsed}\n"
                )

    print(f"Loop finished after {args.max_steps} steps.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
