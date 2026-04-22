import os
import shutil
import stat
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def write_executable(path: Path, content: str) -> None:
    path.write_text(content)
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def make_fake_tmux(bin_dir: Path) -> None:
    write_executable(
        bin_dir / "tmux",
        textwrap.dedent(
            """\
            #!/usr/bin/env python3
            import os
            import subprocess
            import sys
            from pathlib import Path

            root = Path(os.environ["FAKE_TMUX_ROOT"])
            sessions = root / "sessions"
            panes = root / "panes"
            calls = root / "calls.log"
            sessions.mkdir(parents=True, exist_ok=True)
            panes.mkdir(parents=True, exist_ok=True)

            def record(args):
                with calls.open("a") as fh:
                    fh.write(" ".join(args) + "\\n")

            def pane_state_path(target):
                safe = target.replace("/", "_").replace(":", "__")
                return panes / safe

            def pane_stdout_path(target):
                return Path(str(pane_state_path(target)) + ".stdout")

            def pane_stderr_path(target):
                return Path(str(pane_state_path(target)) + ".stderr")

            args = sys.argv[1:]
            record(args)
            if not args:
                sys.exit(1)

            cmd = args[0]
            if cmd == "has-session":
                target = args[args.index("-t") + 1]
                sys.exit(0 if (sessions / target).exists() else 1)

            if cmd == "set-option":
                sys.exit(0)

            if cmd == "list-panes":
                target = args[args.index("-t") + 1]
                state_path = pane_state_path(target)
                dead = "1" if state_path.exists() else "0"
                sys.stdout.write(dead + "\\n")
                sys.exit(0)

            if cmd == "display-message":
                target = args[args.index("-t") + 1]
                state_path = pane_state_path(target)
                if not state_path.exists():
                    sys.exit(1)
                sys.stdout.write(state_path.read_text())
                sys.exit(0)

            if cmd in {"new-session", "new-window"}:
                target = None
                if "-s" in args:
                    target = args[args.index("-s") + 1]
                elif "-t" in args:
                    target = args[args.index("-t") + 1]

                if target:
                    (sessions / target).write_text("")

                if "-n" in args:
                    window_name = args[args.index("-n") + 1]
                    cmd_start = args.index("-n") + 2
                else:
                    window_name = "default"
                    cmd_start = 1
                pane_cmd = args[cmd_start:]
                if pane_cmd:
                    proc = subprocess.run(pane_cmd, check=False, capture_output=True, text=True)
                    if target:
                        pane_target = f"{target}:{window_name}"
                        pane_state_path(pane_target).write_text(f"{proc.returncode}\\n")
                        pane_stdout_path(pane_target).write_text(proc.stdout)
                        pane_stderr_path(pane_target).write_text(proc.stderr)
                    sys.exit(0)
                sys.exit(0)

            sys.exit(0)
            """
        ),
    )


def make_fake_agent(bin_dir: Path, name: str, stdout: str, stderr: str) -> Path:
    path = bin_dir / name
    write_executable(
        path,
        textwrap.dedent(
            f"""\
            #!/usr/bin/env bash
            set -euo pipefail
            cat >/dev/null
            printf {stdout!r}
            printf {stderr!r} >&2
            """
        ),
    )
    return path


def make_fake_input_agent(bin_dir: Path, name: str, stderr: str = "") -> Path:
    path = bin_dir / name
    write_executable(
        path,
        textwrap.dedent(
            f"""\
            #!/usr/bin/env bash
            set -euo pipefail
            cat
            printf {stderr!r} >&2
            """
        ),
    )
    return path


class ConvergeTmuxTests(unittest.TestCase):
    maxDiff = None

    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.bin_dir = self.root / "bin"
        self.bin_dir.mkdir()
        make_fake_tmux(self.bin_dir)
        self.default_agent = make_fake_agent(
            self.bin_dir,
            "fake-agent",
            "agent stdout\n",
            "agent stderr\n",
        )
        self.agent_a = make_fake_agent(
            self.bin_dir,
            "fake-agent-a",
            "agent a stdout\n",
            "agent a stderr\n",
        )
        self.agent_b = make_fake_agent(
            self.bin_dir,
            "fake-agent-b",
            "agent b stdout\n",
            "agent b stderr\n",
        )
        self.input_agent = make_fake_input_agent(self.bin_dir, "fake-input-agent")
        self.fake_tmux_root = self.root / "fake_tmux"
        self.fake_tmux_root.mkdir()

        self.prompt_dir = self.root / "prompts"
        self.prompt_dir.mkdir()
        self.builder_prompt_text = "Write a handoff."
        self.reviewer_prompt_text = "Review the handoff."
        (self.prompt_dir / "builder.md").write_text(self.builder_prompt_text)
        (self.prompt_dir / "reviewer.md").write_text(self.reviewer_prompt_text)
        self.single_prompt_list = self.root / "single-prompts.txt"
        self.single_prompt_list.write_text("./prompts/builder.md\n")
        self.rotation_prompt_list = self.root / "rotation-prompts.txt"
        self.rotation_prompt_list.write_text(
            "./prompts/builder.md\n./prompts/reviewer.md\n./prompts/builder.md\n"
        )

        self.session_dir = self.root / "session"
        self.env = os.environ.copy()
        self.env["PATH"] = f"{self.bin_dir}:{self.env.get('PATH', '')}"
        self.env["FAKE_TMUX_ROOT"] = str(self.fake_tmux_root)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def run_runner(
        self,
        command: list[str],
        *,
        cwd: Path | None = None,
        env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            command,
            cwd=cwd or REPO_ROOT,
            env=env or self.env,
            text=True,
            capture_output=True,
            check=False,
        )

    def make_home_with_bash_profile(self, name: str, content: str) -> Path:
        home_dir = self.root / name
        home_dir.mkdir()
        (home_dir / ".bash_profile").write_text(content)
        return home_dir

    def assert_step_logs_exclude_profile_noise(self, session_dir: Path) -> None:
        step_dir = session_dir / "run" / "s001"
        self.assertNotIn("profile-noise", (step_dir / "stdout.log").read_text())
        self.assertNotIn("profile-noise", (step_dir / "stderr.log").read_text())

    def assert_tmux_run_artifacts(self) -> None:
        step_dir = self.session_dir / "run" / "s001"
        self.assertEqual((step_dir / "stdout.log").read_text(), "agent stdout\n")
        self.assertEqual((step_dir / "stderr.log").read_text(), "agent stderr\n")
        self.assertEqual((step_dir / "exit_code.txt").read_text(), "0\n")
        calls_log = (self.fake_tmux_root / "calls.log").read_text()
        self.assertIn("new-session", calls_log)
        self.assertIn("set-option", calls_log)

    def assert_tmux_windows_are_preserved_per_step(self, result: subprocess.CompletedProcess[str], session_name: str) -> None:
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn(f"tmux_session={session_name}", result.stdout)
        calls = (self.fake_tmux_root / "calls.log").read_text().splitlines()
        self.assertIn(
            f"set-option -t {session_name}:s001-builder remain-on-exit on",
            calls,
        )
        self.assertIn(
            f"set-option -t {session_name}:s002-builder remain-on-exit on",
            calls,
        )
        self.assertIn(
            f"set-option -t {session_name}:s001-builder automatic-rename off",
            calls,
        )
        self.assertIn(
            f"set-option -t {session_name}:s002-builder automatic-rename off",
            calls,
        )
        self.assertEqual((self.session_dir / "run" / "s002" / "exit_code.txt").read_text(), "0\n")

    def assert_independent_rotation(self, result: subprocess.CompletedProcess[str]) -> None:
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        expected_steps = [
            (
                "s001",
                self.prompt_dir / "builder.md",
                self.builder_prompt_text,
                self.agent_a,
                "agent a stdout\n",
                "agent a stderr\n",
            ),
            (
                "s002",
                self.prompt_dir / "reviewer.md",
                self.reviewer_prompt_text,
                self.agent_b,
                "agent b stdout\n",
                "agent b stderr\n",
            ),
            (
                "s003",
                self.prompt_dir / "builder.md",
                self.builder_prompt_text,
                self.agent_a,
                "agent a stdout\n",
                "agent a stderr\n",
            ),
            (
                "s004",
                self.prompt_dir / "builder.md",
                self.builder_prompt_text,
                self.agent_b,
                "agent b stdout\n",
                "agent b stderr\n",
            ),
        ]
        for step_id, prompt_path, prompt_text, agent_cmd, stdout_text, stderr_text in expected_steps:
            step_dir = self.session_dir / "run" / step_id
            effective_prompt = (step_dir / "effective_prompt.md").read_text()
            with self.subTest(step=step_id, property="stdout.log"):
                self.assertEqual((step_dir / "stdout.log").read_text(), stdout_text)
            with self.subTest(step=step_id, property="stderr.log"):
                self.assertEqual((step_dir / "stderr.log").read_text(), stderr_text)
            with self.subTest(step=step_id, property="exit_code.txt"):
                self.assertEqual((step_dir / "exit_code.txt").read_text(), "0\n")
            with self.subTest(step=step_id, property="effective_prompt prompt"):
                self.assertIn(prompt_text, effective_prompt)
            with self.subTest(step=step_id, property="effective_prompt agent_cmd"):
                self.assertIn("- agent_cmd:", effective_prompt)
                self.assertIn(agent_cmd.name, effective_prompt)

        loop_lines = (self.session_dir / "run" / "loop" / "loop.log").read_text().splitlines()
        self.assertEqual(len(loop_lines), 4)
        for step_number, (_, prompt_path, _, agent_cmd, _, _) in enumerate(
            expected_steps, start=1
        ):
            loop_line = loop_lines[step_number - 1]
            logged_prompt = Path(loop_line.split("prompt=", 1)[1].split(" ", 1)[0])
            with self.subTest(step=step_number, property="loop.log step"):
                self.assertIn(f"step={step_number}", loop_line)
            with self.subTest(step=step_number, property="loop.log prompt"):
                self.assertEqual(
                    logged_prompt.resolve(),
                    prompt_path.resolve(),
                    msg=f"{loop_line!r} logged unexpected prompt path",
                )
            with self.subTest(step=step_number, property="loop.log agent_cmd"):
                self.assertIn("agent_cmd=", loop_line)
                self.assertIn(agent_cmd.name, loop_line)
            with self.subTest(step=step_number, property="loop.log exit"):
                self.assertIn("exit=0", loop_line)

    def assert_runner_without_session_dir_omits_artifacts(
        self,
        command: list[str],
        *,
        cwd: Path | None = None,
        expect_tmux: bool = False,
    ) -> None:
        result = self.run_runner(command, cwd=cwd or self.root)

        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertNotIn("session_dir=", result.stdout)
        self.assertNotIn("input_handoff", result.stdout)
        self.assertNotIn("output_handoff", result.stdout)
        if expect_tmux:
            self.assertIn("tmux_session=", result.stdout)
            self.assertIn("tmux attach -t", result.stdout)
            session_name = next(
                line.split("=", 1)[1]
                for line in result.stdout.splitlines()
                if line.startswith("tmux_session=")
            )
            pane_base = (
                self.fake_tmux_root
                / "panes"
                / f"{session_name}__s001-builder"
            )
            pane_stdout = pane_base.with_suffix(".stdout").read_text()
            self.assertIn(self.builder_prompt_text, pane_stdout)
            self.assertNotIn("input_handoff", pane_stdout)
            self.assertNotIn("output_handoff", pane_stdout)
        self.assertFalse(((cwd or self.root) / "run").exists())

    def assert_runner_without_handoff_keeps_session_artifacts(
        self, command: list[str]
    ) -> None:
        result = self.run_runner(command)

        self.assertEqual(result.returncode, 0, msg=result.stderr)
        reported_session_dir = next(
            Path(line.split("=", 1)[1])
            for line in result.stdout.splitlines()
            if line.startswith("session_dir=")
        )
        self.assertEqual(reported_session_dir.resolve(), self.session_dir.resolve())
        step_one_dir = self.session_dir / "run" / "s001"
        step_two_dir = self.session_dir / "run" / "s002"
        self.assertFalse((step_one_dir / "handoff.md").exists())
        self.assertFalse((step_two_dir / "handoff.md").exists())
        self.assertTrue((step_one_dir / "effective_prompt.md").is_file())
        self.assertTrue((step_two_dir / "effective_prompt.md").is_file())
        self.assertTrue((step_one_dir / "stdout.log").is_file())
        self.assertTrue((step_one_dir / "stderr.log").is_file())
        self.assertTrue((step_one_dir / "exit_code.txt").is_file())
        self.assertNotIn("input_handoff", (step_one_dir / "effective_prompt.md").read_text())
        self.assertNotIn("output_handoff", (step_one_dir / "effective_prompt.md").read_text())
        self.assertNotIn("input_handoff", (step_two_dir / "effective_prompt.md").read_text())
        self.assertNotIn("output_handoff", (step_two_dir / "effective_prompt.md").read_text())

    def assert_tmux_runner_without_handoff_keeps_session_artifacts(
        self, command: list[str]
    ) -> None:
        result = self.run_runner(command)

        self.assertEqual(result.returncode, 0, msg=result.stderr)
        reported_session_dir = next(
            Path(line.split("=", 1)[1])
            for line in result.stdout.splitlines()
            if line.startswith("session_dir=")
        )
        self.assertEqual(reported_session_dir.resolve(), self.session_dir.resolve())
        self.assertIn("tmux_session=", result.stdout)
        step_one_dir = self.session_dir / "run" / "s001"
        step_two_dir = self.session_dir / "run" / "s002"
        self.assertFalse((step_one_dir / "handoff.md").exists())
        self.assertFalse((step_two_dir / "handoff.md").exists())
        self.assertTrue((step_one_dir / "stdout.log").is_file())
        self.assertTrue((step_one_dir / "stderr.log").is_file())
        self.assertEqual((step_one_dir / "stdout.log").read_text(), "agent stdout\n")
        self.assertEqual((step_one_dir / "stderr.log").read_text(), "agent stderr\n")
        self.assertFalse((step_one_dir / "tmux_step.sh").exists())
        self.assertEqual((step_one_dir / "exit_code.txt").read_text(), "0\n")
        self.assertEqual((step_two_dir / "exit_code.txt").read_text(), "0\n")
        self.assertNotIn("input_handoff", (step_one_dir / "effective_prompt.md").read_text())
        self.assertNotIn("output_handoff", (step_one_dir / "effective_prompt.md").read_text())
        self.assertNotIn("input_handoff", (step_two_dir / "effective_prompt.md").read_text())
        self.assertNotIn("output_handoff", (step_two_dir / "effective_prompt.md").read_text())

    def assert_runner_requires_session_dir_for_handoff(self, command: list[str]) -> None:
        result = self.run_runner(command, cwd=self.root)

        combined_output = result.stdout + result.stderr
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--handoff requires --session-dir", combined_output)

    def test_python_runner_without_tmux_still_writes_logs(self) -> None:
        result = self.run_runner(
            [
                "python3",
                "scripts/converge.py",
                "--session-dir",
                str(self.session_dir),
                "--prompt-list",
                str(self.single_prompt_list),
                "--agent-cmd",
                str(self.default_agent),
                "--max-steps",
                "1",
            ]
        )

        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertNotIn("tmux_session=", result.stdout)
        step_dir = self.session_dir / "run" / "s001"
        self.assertEqual((step_dir / "stdout.log").read_text(), "agent stdout\n")
        self.assertEqual((step_dir / "stderr.log").read_text(), "agent stderr\n")
        self.assertEqual((step_dir / "exit_code.txt").read_text(), "0\n")

    def test_python_runner_without_session_dir_omits_artifacts(self) -> None:
        self.assert_runner_without_session_dir_omits_artifacts(
            [
                "python3",
                str(REPO_ROOT / "scripts/converge.py"),
                "--prompt-list",
                str(self.single_prompt_list),
                "--agent-cmd",
                str(self.input_agent),
                "--max-steps",
                "1",
            ]
        )

    def test_python_runner_with_session_dir_can_disable_handoff(self) -> None:
        self.assert_runner_without_handoff_keeps_session_artifacts(
            [
                "python3",
                "scripts/converge.py",
                "--session-dir",
                str(self.session_dir),
                "--prompt-list",
                str(self.rotation_prompt_list),
                "--agent-cmd",
                str(self.default_agent),
                "--max-steps",
                "2",
                "--no-handoff",
            ]
        )

    def test_python_runner_without_session_dir_supports_tmux_without_artifacts(self) -> None:
        self.assert_runner_without_session_dir_omits_artifacts(
            [
                "python3",
                str(REPO_ROOT / "scripts/converge.py"),
                "--prompt-list",
                str(self.single_prompt_list),
                "--agent-cmd",
                str(self.input_agent),
                "--max-steps",
                "1",
                "--tmux",
            ],
            expect_tmux=True,
        )

    def test_python_runner_tmux_with_session_dir_can_disable_handoff_without_tmux_artifacts(self) -> None:
        self.assert_tmux_runner_without_handoff_keeps_session_artifacts(
            [
                "python3",
                "scripts/converge.py",
                "--session-dir",
                str(self.session_dir),
                "--prompt-list",
                str(self.rotation_prompt_list),
                "--agent-cmd",
                str(self.default_agent),
                "--max-steps",
                "2",
                "--tmux",
                "--no-handoff",
            ]
        )

    def test_python_runner_requires_session_dir_when_handoff_is_forced(self) -> None:
        self.assert_runner_requires_session_dir_for_handoff(
            [
                "python3",
                str(REPO_ROOT / "scripts/converge.py"),
                "--prompt-list",
                str(self.single_prompt_list),
                "--agent-cmd",
                str(self.default_agent),
                "--max-steps",
                "1",
                "--handoff",
            ]
        )

    def test_python_runner_does_not_source_login_shell_profiles(self) -> None:
        env = self.env.copy()
        env["HOME"] = str(
            self.make_home_with_bash_profile("python-home", "echo profile-noise\n")
        )

        for mode in ("without-tmux", "with-tmux"):
            with self.subTest(mode=mode):
                session_dir = self.root / f"python-profile-{mode}"
                command = [
                    "python3",
                    "scripts/converge.py",
                    "--session-dir",
                    str(session_dir),
                    "--prompt-list",
                    str(self.single_prompt_list),
                    "--agent-cmd",
                    str(self.default_agent),
                    "--max-steps",
                    "1",
                ]
                if mode == "with-tmux":
                    command.append("--tmux")

                result = self.run_runner(command, env=env)

                self.assertEqual(result.returncode, 0, msg=result.stderr)
                self.assert_step_logs_exclude_profile_noise(session_dir)

    def test_python_runner_tmux_mode_keeps_live_output_and_logs(self) -> None:
        result = self.run_runner(
            [
                "python3",
                "scripts/converge.py",
                "--session-dir",
                str(self.session_dir),
                "--prompt-list",
                str(self.single_prompt_list),
                "--agent-cmd",
                str(self.default_agent),
                "--max-steps",
                "1",
                "--tmux",
            ]
        )

        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("tmux_session=", result.stdout)
        self.assertIn("tmux attach -t", result.stdout)
        self.assert_tmux_run_artifacts()

    def test_python_runner_tmux_mode_preserves_each_step_window(self) -> None:
        session_name = "python-window-test"
        result = self.run_runner(
            [
                "python3",
                "scripts/converge.py",
                "--session-dir",
                str(self.session_dir),
                "--prompt-list",
                str(self.single_prompt_list),
                "--agent-cmd",
                str(self.default_agent),
                "--max-steps",
                "2",
                "--tmux",
                "--tmux-session-name",
                session_name,
            ]
        )

        self.assert_tmux_windows_are_preserved_per_step(result, session_name)

    def test_python_runner_tmux_mode_prints_shell_escaped_attach_command(self) -> None:
        session_name = "python session name"
        result = self.run_runner(
            [
                "python3",
                "scripts/converge.py",
                "--session-dir",
                str(self.session_dir),
                "--prompt-list",
                str(self.single_prompt_list),
                "--agent-cmd",
                str(self.default_agent),
                "--max-steps",
                "1",
                "--tmux",
                "--tmux-session-name",
                session_name,
            ]
        )

        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn(f"tmux_session={session_name}", result.stdout)
        self.assertIn(
            "tmux_attach_cmd=tmux attach -t python\\ session\\ name",
            result.stdout,
        )

    def test_shell_runner_tmux_mode_keeps_live_output_and_logs(self) -> None:
        result = self.run_runner(
            [
                "bash",
                "scripts/converge.sh",
                "--session-dir",
                str(self.session_dir),
                "--prompt-list",
                str(self.single_prompt_list),
                "--agent-cmd",
                str(self.default_agent),
                "--max-steps",
                "1",
                "--tmux",
            ]
        )

        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("tmux_session=", result.stdout)
        self.assertIn("tmux attach -t", result.stdout)
        self.assert_tmux_run_artifacts()

    def test_shell_runner_without_session_dir_omits_artifacts(self) -> None:
        self.assert_runner_without_session_dir_omits_artifacts(
            [
                "bash",
                str(REPO_ROOT / "scripts/converge.sh"),
                "--prompt-list",
                str(self.single_prompt_list),
                "--agent-cmd",
                str(self.input_agent),
                "--max-steps",
                "1",
            ]
        )

    def test_shell_runner_with_session_dir_can_disable_handoff(self) -> None:
        self.assert_runner_without_handoff_keeps_session_artifacts(
            [
                "bash",
                "scripts/converge.sh",
                "--session-dir",
                str(self.session_dir),
                "--prompt-list",
                str(self.rotation_prompt_list),
                "--agent-cmd",
                str(self.default_agent),
                "--max-steps",
                "2",
                "--no-handoff",
            ]
        )

    def test_shell_runner_without_session_dir_supports_tmux_without_artifacts(self) -> None:
        self.assert_runner_without_session_dir_omits_artifacts(
            [
                "bash",
                str(REPO_ROOT / "scripts/converge.sh"),
                "--prompt-list",
                str(self.single_prompt_list),
                "--agent-cmd",
                str(self.input_agent),
                "--max-steps",
                "1",
                "--tmux",
            ],
            expect_tmux=True,
        )

    def test_shell_runner_tmux_with_session_dir_can_disable_handoff_without_tmux_artifacts(self) -> None:
        self.assert_tmux_runner_without_handoff_keeps_session_artifacts(
            [
                "bash",
                "scripts/converge.sh",
                "--session-dir",
                str(self.session_dir),
                "--prompt-list",
                str(self.rotation_prompt_list),
                "--agent-cmd",
                str(self.default_agent),
                "--max-steps",
                "2",
                "--tmux",
                "--no-handoff",
            ]
        )

    def test_shell_runner_requires_session_dir_when_handoff_is_forced(self) -> None:
        self.assert_runner_requires_session_dir_for_handoff(
            [
                "bash",
                str(REPO_ROOT / "scripts/converge.sh"),
                "--prompt-list",
                str(self.single_prompt_list),
                "--agent-cmd",
                str(self.default_agent),
                "--max-steps",
                "1",
                "--handoff",
            ]
        )

    def test_shell_runner_tmux_mode_preserves_each_step_window(self) -> None:
        session_name = "shell-window-test"
        result = self.run_runner(
            [
                "bash",
                "scripts/converge.sh",
                "--session-dir",
                str(self.session_dir),
                "--prompt-list",
                str(self.single_prompt_list),
                "--agent-cmd",
                str(self.default_agent),
                "--max-steps",
                "2",
                "--tmux",
                "--tmux-session-name",
                session_name,
            ]
        )

        self.assert_tmux_windows_are_preserved_per_step(result, session_name)

    def test_shell_runner_tmux_mode_prints_shell_escaped_attach_command(self) -> None:
        session_name = "shell session name"
        result = self.run_runner(
            [
                "bash",
                "scripts/converge.sh",
                "--session-dir",
                str(self.session_dir),
                "--prompt-list",
                str(self.single_prompt_list),
                "--agent-cmd",
                str(self.default_agent),
                "--max-steps",
                "1",
                "--tmux",
                "--tmux-session-name",
                session_name,
            ]
        )

        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn(f"tmux_session={session_name}", result.stdout)
        self.assertIn(
            "tmux_attach_cmd=tmux attach -t shell\\ session\\ name",
            result.stdout,
        )

    def test_shell_runner_does_not_source_login_shell_profiles(self) -> None:
        env = self.env.copy()
        env["HOME"] = str(
            self.make_home_with_bash_profile("shell-home", "echo profile-noise\n")
        )

        for mode in ("without-tmux", "with-tmux"):
            with self.subTest(mode=mode):
                session_dir = self.root / f"shell-profile-{mode}"
                command = [
                    "bash",
                    "scripts/converge.sh",
                    "--session-dir",
                    str(session_dir),
                    "--prompt-list",
                    str(self.single_prompt_list),
                    "--agent-cmd",
                    str(self.default_agent),
                    "--max-steps",
                    "1",
                ]
                if mode == "with-tmux":
                    command.append("--tmux")

                result = self.run_runner(command, env=env)

                self.assertEqual(result.returncode, 0, msg=result.stderr)
                self.assert_step_logs_exclude_profile_noise(session_dir)

    def test_shell_runner_rotates_agent_commands_independently_without_tmux(self) -> None:
        result = self.run_runner(
            [
                "bash",
                "scripts/converge.sh",
                "--session-dir",
                str(self.session_dir),
                "--prompt-list",
                str(self.rotation_prompt_list),
                "--agent-cmd",
                str(self.agent_a),
                "--agent-cmd",
                str(self.agent_b),
                "--max-steps",
                "4",
            ]
        )

        self.assertNotIn("tmux_session=", result.stdout)
        self.assert_independent_rotation(result)

    def test_shell_runner_rotates_agent_commands_independently_with_tmux(self) -> None:
        result = self.run_runner(
            [
                "bash",
                "scripts/converge.sh",
                "--session-dir",
                str(self.session_dir),
                "--prompt-list",
                str(self.rotation_prompt_list),
                "--agent-cmd",
                str(self.agent_a),
                "--agent-cmd",
                str(self.agent_b),
                "--max-steps",
                "4",
                "--tmux",
            ]
        )

        self.assertIn("new-session", (self.fake_tmux_root / "calls.log").read_text())
        self.assert_independent_rotation(result)

    def test_ruby_runner_tmux_mode_keeps_live_output_and_logs(self) -> None:
        if shutil.which("ruby") is None:
            self.skipTest("ruby is not installed")

        result = self.run_runner(
            [
                "ruby",
                "scripts/converge.rb",
                "--session-dir",
                str(self.session_dir),
                "--prompt-list",
                str(self.single_prompt_list),
                "--agent-cmd",
                str(self.default_agent),
                "--max-steps",
                "1",
                "--tmux",
            ]
        )

        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("tmux_session=", result.stdout)
        self.assertIn("tmux attach -t", result.stdout)
        self.assert_tmux_run_artifacts()

    def test_ruby_runner_without_session_dir_omits_artifacts(self) -> None:
        if shutil.which("ruby") is None:
            self.skipTest("ruby is not installed")

        self.assert_runner_without_session_dir_omits_artifacts(
            [
                "ruby",
                str(REPO_ROOT / "scripts/converge.rb"),
                "--prompt-list",
                str(self.single_prompt_list),
                "--agent-cmd",
                str(self.input_agent),
                "--max-steps",
                "1",
            ]
        )

    def test_ruby_runner_with_session_dir_can_disable_handoff(self) -> None:
        if shutil.which("ruby") is None:
            self.skipTest("ruby is not installed")

        self.assert_runner_without_handoff_keeps_session_artifacts(
            [
                "ruby",
                "scripts/converge.rb",
                "--session-dir",
                str(self.session_dir),
                "--prompt-list",
                str(self.rotation_prompt_list),
                "--agent-cmd",
                str(self.default_agent),
                "--max-steps",
                "2",
                "--no-handoff",
            ]
        )

    def test_ruby_runner_without_session_dir_supports_tmux_without_artifacts(self) -> None:
        if shutil.which("ruby") is None:
            self.skipTest("ruby is not installed")

        self.assert_runner_without_session_dir_omits_artifacts(
            [
                "ruby",
                str(REPO_ROOT / "scripts/converge.rb"),
                "--prompt-list",
                str(self.single_prompt_list),
                "--agent-cmd",
                str(self.input_agent),
                "--max-steps",
                "1",
                "--tmux",
            ],
            expect_tmux=True,
        )

    def test_ruby_runner_tmux_with_session_dir_can_disable_handoff_without_tmux_artifacts(self) -> None:
        if shutil.which("ruby") is None:
            self.skipTest("ruby is not installed")

        self.assert_tmux_runner_without_handoff_keeps_session_artifacts(
            [
                "ruby",
                "scripts/converge.rb",
                "--session-dir",
                str(self.session_dir),
                "--prompt-list",
                str(self.rotation_prompt_list),
                "--agent-cmd",
                str(self.default_agent),
                "--max-steps",
                "2",
                "--tmux",
                "--no-handoff",
            ]
        )

    def test_ruby_runner_requires_session_dir_when_handoff_is_forced(self) -> None:
        if shutil.which("ruby") is None:
            self.skipTest("ruby is not installed")

        self.assert_runner_requires_session_dir_for_handoff(
            [
                "ruby",
                str(REPO_ROOT / "scripts/converge.rb"),
                "--prompt-list",
                str(self.single_prompt_list),
                "--agent-cmd",
                str(self.default_agent),
                "--max-steps",
                "1",
                "--handoff",
            ]
        )

    def test_ruby_runner_tmux_mode_preserves_each_step_window(self) -> None:
        if shutil.which("ruby") is None:
            self.skipTest("ruby is not installed")

        session_name = "ruby-window-test"
        result = self.run_runner(
            [
                "ruby",
                "scripts/converge.rb",
                "--session-dir",
                str(self.session_dir),
                "--prompt-list",
                str(self.single_prompt_list),
                "--agent-cmd",
                str(self.default_agent),
                "--max-steps",
                "2",
                "--tmux",
                "--tmux-session-name",
                session_name,
            ]
        )

        self.assert_tmux_windows_are_preserved_per_step(result, session_name)

    def test_ruby_runner_tmux_mode_prints_shell_escaped_attach_command(self) -> None:
        if shutil.which("ruby") is None:
            self.skipTest("ruby is not installed")

        session_name = "ruby session name"
        result = self.run_runner(
            [
                "ruby",
                "scripts/converge.rb",
                "--session-dir",
                str(self.session_dir),
                "--prompt-list",
                str(self.single_prompt_list),
                "--agent-cmd",
                str(self.default_agent),
                "--max-steps",
                "1",
                "--tmux",
                "--tmux-session-name",
                session_name,
            ]
        )

        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn(f"tmux_session={session_name}", result.stdout)
        self.assertIn(
            "tmux_attach_cmd=tmux attach -t ruby\\ session\\ name",
            result.stdout,
        )

    def test_ruby_runner_without_tmux_redirects_entire_shell_snippet(self) -> None:
        if shutil.which("ruby") is None:
            self.skipTest("ruby is not installed")

        result = self.run_runner(
            [
                "ruby",
                "scripts/converge.rb",
                "--session-dir",
                str(self.session_dir),
                "--prompt-list",
                str(self.single_prompt_list),
                "--agent-cmd",
                "cat >/dev/null; printf 'compound stdout\\n'; printf 'compound stderr\\n' >&2",
                "--max-steps",
                "1",
            ]
        )

        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertEqual(result.stdout.count("compound stdout"), 1)
        self.assertNotIn("compound stderr", result.stderr)
        step_dir = self.session_dir / "run" / "s001"
        self.assertEqual((step_dir / "stdout.log").read_text(), "compound stdout\n")
        self.assertEqual((step_dir / "stderr.log").read_text(), "compound stderr\n")
        self.assertEqual((step_dir / "exit_code.txt").read_text(), "0\n")

    def test_ruby_runner_does_not_source_login_shell_profiles(self) -> None:
        if shutil.which("ruby") is None:
            self.skipTest("ruby is not installed")

        env = self.env.copy()
        env["HOME"] = str(
            self.make_home_with_bash_profile("ruby-home", "echo profile-noise\n")
        )

        for mode in ("without-tmux", "with-tmux"):
            with self.subTest(mode=mode):
                session_dir = self.root / f"ruby-profile-{mode}"
                command = [
                    "ruby",
                    "scripts/converge.rb",
                    "--session-dir",
                    str(session_dir),
                    "--prompt-list",
                    str(self.single_prompt_list),
                    "--agent-cmd",
                    str(self.default_agent),
                    "--max-steps",
                    "1",
                ]
                if mode == "with-tmux":
                    command.append("--tmux")

                result = self.run_runner(command, env=env)

                self.assertEqual(result.returncode, 0, msg=result.stderr)
                self.assert_step_logs_exclude_profile_noise(session_dir)

    def test_ruby_runner_requires_value_after_agent_cmd(self) -> None:
        if shutil.which("ruby") is None:
            self.skipTest("ruby is not installed")

        result = self.run_runner(
            [
                "ruby",
                "scripts/converge.rb",
                "--session-dir",
                str(self.session_dir),
                "--prompt-list",
                str(self.single_prompt_list),
                "--agent-cmd",
            ]
        )

        combined_output = result.stdout + result.stderr
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("TypeError", combined_output)
        self.assertIn("Missing value for --agent-cmd", combined_output)
        self.assertIn("USAGE", combined_output)

    def test_ruby_runner_rejects_empty_agent_cmd(self) -> None:
        if shutil.which("ruby") is None:
            self.skipTest("ruby is not installed")

        result = self.run_runner(
            [
                "ruby",
                "scripts/converge.rb",
                "--session-dir",
                str(self.session_dir),
                "--prompt-list",
                str(self.single_prompt_list),
                "--agent-cmd",
                "",
            ]
        )

        combined_output = result.stdout + result.stderr
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("TypeError", combined_output)
        self.assertIn("Invalid value for --agent-cmd", combined_output)
        self.assertIn("USAGE", combined_output)

    def test_ruby_runner_rotates_agent_commands_independently_without_tmux(self) -> None:
        if shutil.which("ruby") is None:
            self.skipTest("ruby is not installed")

        result = self.run_runner(
            [
                "ruby",
                "scripts/converge.rb",
                "--session-dir",
                str(self.session_dir),
                "--prompt-list",
                str(self.rotation_prompt_list),
                "--agent-cmd",
                str(self.agent_a),
                "--agent-cmd",
                str(self.agent_b),
                "--max-steps",
                "4",
            ]
        )

        self.assertNotIn("tmux_session=", result.stdout)
        self.assert_independent_rotation(result)

    def test_ruby_runner_rotates_agent_commands_independently_with_tmux(self) -> None:
        if shutil.which("ruby") is None:
            self.skipTest("ruby is not installed")

        result = self.run_runner(
            [
                "ruby",
                "scripts/converge.rb",
                "--session-dir",
                str(self.session_dir),
                "--prompt-list",
                str(self.rotation_prompt_list),
                "--agent-cmd",
                str(self.agent_a),
                "--agent-cmd",
                str(self.agent_b),
                "--max-steps",
                "4",
                "--tmux",
            ]
        )

        self.assertIn("new-session", (self.fake_tmux_root / "calls.log").read_text())
        self.assert_independent_rotation(result)

    def test_python_runner_rotates_agent_commands_independently_without_tmux(self) -> None:
        result = self.run_runner(
            [
                "python3",
                "scripts/converge.py",
                "--session-dir",
                str(self.session_dir),
                "--prompt-list",
                str(self.rotation_prompt_list),
                "--agent-cmd",
                str(self.agent_a),
                "--agent-cmd",
                str(self.agent_b),
                "--max-steps",
                "4",
            ]
        )

        self.assertNotIn("tmux_session=", result.stdout)
        self.assert_independent_rotation(result)

    def test_python_runner_rotates_agent_commands_independently_with_tmux(self) -> None:
        result = self.run_runner(
            [
                "python3",
                "scripts/converge.py",
                "--session-dir",
                str(self.session_dir),
                "--prompt-list",
                str(self.rotation_prompt_list),
                "--agent-cmd",
                str(self.agent_a),
                "--agent-cmd",
                str(self.agent_b),
                "--max-steps",
                "4",
                "--tmux",
            ]
        )

        self.assertIn("tmux_session=", result.stdout)
        self.assertIn("tmux attach -t", result.stdout)
        self.assert_independent_rotation(result)
