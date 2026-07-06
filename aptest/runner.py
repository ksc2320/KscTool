#!/usr/bin/env python3
"""Run AP debug suites over SSH or emit an AP-side shell script."""

from __future__ import annotations

import argparse
import datetime as _dt
import json
import os
import re
import shlex
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any


@dataclass
class StepResult:
    name: str
    command: str
    returncode: int | None
    passed: bool
    elapsed_sec: float
    stdout: str
    stderr: str
    reason: str
    saved_to: str | None = None


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def shell_split(value: str) -> list[str]:
    return shlex.split(os.path.expanduser(value)) if value else []


def build_ssh_command(args: argparse.Namespace, remote_command: str) -> list[str]:
    ssh_cmd = [
        "ssh",
        "-p",
        str(args.port),
        "-o",
        f"ConnectTimeout={args.connect_timeout}",
    ]
    ssh_cmd.extend(shell_split(args.ssh_options))
    ssh_cmd.append(f"{args.user}@{args.host}")
    ssh_cmd.append("sh -lc " + shlex.quote(remote_command))
    if args.password:
        return ["sshpass", "-e", *ssh_cmd]
    return ssh_cmd


def display_command(cmd: list[str], has_password: bool) -> str:
    if has_password and cmd[:2] == ["sshpass", "-e"]:
        shown = ["sshpass", "-e", *cmd[2:]]
    else:
        shown = cmd
    return " ".join(shlex.quote(part) for part in shown)


def check_result(step: dict[str, Any], returncode: int, output: str) -> tuple[bool, str]:
    expected_exit = int(step.get("expect_exit", 0))
    if returncode != expected_exit:
        return False, f"exit {returncode}, expected {expected_exit}"

    expect_regex = step.get("expect_regex")
    if expect_regex and not re.search(str(expect_regex), output, re.MULTILINE):
        return False, f"missing regex: {expect_regex}"

    reject_regex = step.get("reject_regex")
    if reject_regex and re.search(str(reject_regex), output, re.MULTILINE):
        return False, f"rejected regex matched: {reject_regex}"

    return True, "ok"


def save_step_output(artifact_dir: Path, step: dict[str, Any], stdout: str, stderr: str) -> str | None:
    save_as = step.get("save_as")
    if not save_as:
        return None
    path = artifact_dir / str(save_as).replace("/", "_")
    path.write_text("### stdout\n" + stdout + "\n### stderr\n" + stderr, encoding="utf-8")
    return str(path)


def run_suite(args: argparse.Namespace) -> int:
    suite = load_json(Path(args.suite))
    password = args.password or os.environ.get("APTEST_SSH_PASSWORD_VALUE", "")
    stamp = _dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    suite_name = suite.get("name", "suite")
    artifact_dir = Path(args.artifacts_dir).expanduser() / f"{stamp}_{suite_name}"
    if not args.dry_run:
        artifact_dir.mkdir(parents=True, exist_ok=True)

    results: list[StepResult] = []
    failed = False

    for index, step in enumerate(suite.get("steps", []), start=1):
        name = str(step.get("name", f"step-{index}"))
        command = str(step["command"])
        timeout = int(step.get("timeout", args.command_timeout))

        args.password = password
        ssh_cmd = build_ssh_command(args, command)
        if args.dry_run:
            print(f"[dry-run] {name}: {display_command(ssh_cmd, bool(password))}")
            continue

        print(f"[{index:02d}] {name} ... ", end="", flush=True)
        started = _dt.datetime.now()
        try:
            proc = subprocess.run(
                ssh_cmd,
                text=True,
                capture_output=True,
                timeout=timeout,
                check=False,
                env={**os.environ, **({"SSHPASS": password} if password else {})},
            )
            elapsed = (_dt.datetime.now() - started).total_seconds()
            combined = proc.stdout + "\n" + proc.stderr
            passed, reason = check_result(step, proc.returncode, combined)
            saved_to = save_step_output(artifact_dir, step, proc.stdout, proc.stderr)
            result = StepResult(
                name=name,
                command=command,
                returncode=proc.returncode,
                passed=passed,
                elapsed_sec=elapsed,
                stdout=proc.stdout,
                stderr=proc.stderr,
                reason=reason,
                saved_to=saved_to,
            )
        except subprocess.TimeoutExpired as exc:
            elapsed = (_dt.datetime.now() - started).total_seconds()
            stdout = exc.stdout or ""
            stderr = exc.stderr or ""
            result = StepResult(
                name=name,
                command=command,
                returncode=None,
                passed=False,
                elapsed_sec=elapsed,
                stdout=stdout,
                stderr=stderr,
                reason=f"timeout after {timeout}s",
                saved_to=save_step_output(artifact_dir, step, stdout, stderr),
            )

        results.append(result)
        print("PASS" if result.passed else f"FAIL ({result.reason})")

        if not result.passed:
            failed = True
            if step.get("critical", True) and not args.keep_going:
                break

    if args.dry_run:
        return 0

    report = {
        "suite": suite_name,
        "description": suite.get("description", ""),
        "started_at": stamp,
        "artifact_dir": str(artifact_dir),
        "passed": not failed,
        "results": [asdict(result) for result in results],
    }
    (artifact_dir / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    write_text_report(artifact_dir / "report.txt", report)
    print(f"\nartifacts: {artifact_dir}")
    return 1 if failed else 0


def write_text_report(path: Path, report: dict[str, Any]) -> None:
    lines = [
        f"suite: {report['suite']}",
        f"passed: {report['passed']}",
        f"artifact_dir: {report['artifact_dir']}",
        "",
    ]
    for result in report["results"]:
        status = "PASS" if result["passed"] else "FAIL"
        lines.append(f"[{status}] {result['name']} ({result['elapsed_sec']:.2f}s)")
        lines.append(f"  reason: {result['reason']}")
        if result.get("saved_to"):
            lines.append(f"  saved_to: {result['saved_to']}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def emit_ap_script(args: argparse.Namespace) -> int:
    suite = load_json(Path(args.suite))
    suite_name = suite.get("name", "suite")
    out_path = Path(args.emit_ap_script)
    remote_log = f"/tmp/aptest_{suite_name}.log"

    lines = [
        "#!/bin/sh",
        "set +e",
        f"LOG={shlex.quote(remote_log)}",
        ": > \"$LOG\"",
        "pass=0",
        "fail=0",
        "run_step() {",
        "  name=\"$1\"",
        "  cmd=\"$2\"",
        "  expect_exit=\"$3\"",
        "  expect_re=\"$4\"",
        "  reject_re=\"$5\"",
        "  tmp=\"/tmp/aptest_step.$$\"",
        "  echo \"## $name\" >> \"$LOG\"",
        "  sh -lc \"$cmd\" > \"$tmp\" 2>&1",
        "  rc=$?",
        "  cat \"$tmp\" >> \"$LOG\"",
        "  ok=1",
        "  reason=ok",
        "  if [ \"$rc\" != \"$expect_exit\" ]; then ok=0; reason=\"exit $rc expected $expect_exit\"; fi",
        "  if [ \"$ok\" = 1 ] && [ -n \"$expect_re\" ] && ! grep -E \"$expect_re\" \"$tmp\" >/dev/null 2>&1; then ok=0; reason=\"missing regex $expect_re\"; fi",
        "  if [ \"$ok\" = 1 ] && [ -n \"$reject_re\" ] && grep -E \"$reject_re\" \"$tmp\" >/dev/null 2>&1; then ok=0; reason=\"rejected regex $reject_re\"; fi",
        "  if [ \"$ok\" = 1 ]; then echo \"PASS $name\" >> \"$LOG\"; pass=$((pass+1)); else echo \"FAIL $name: $reason\" >> \"$LOG\"; fail=$((fail+1)); fi",
        "  rm -f \"$tmp\"",
        "}",
        "",
    ]

    for step in suite.get("steps", []):
        lines.append(
            "run_step "
            + shlex.quote(str(step.get("name", "step")))
            + " "
            + shlex.quote(str(step["command"]))
            + " "
            + shlex.quote(str(step.get("expect_exit", 0)))
            + " "
            + shlex.quote(str(step.get("expect_regex", "")))
            + " "
            + shlex.quote(str(step.get("reject_regex", "")))
        )

    lines.extend(["", "echo \"summary: pass=$pass fail=$fail\" >> \"$LOG\"", "echo \"$LOG\"", "exit 0"])
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote AP-side script: {out_path}")
    print(f"AP log path after execution: {remote_log}")
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", required=True)
    parser.add_argument("--host", required=True)
    parser.add_argument("--user", default="root")
    parser.add_argument("--port", default="22")
    parser.add_argument("--connect-timeout", default="5")
    parser.add_argument("--command-timeout", default="20")
    parser.add_argument("--ssh-options", default="")
    parser.add_argument("--password", default="")
    parser.add_argument("--artifacts-dir", required=True)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--keep-going", action="store_true")
    parser.add_argument("--emit-ap-script")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.emit_ap_script:
        return emit_ap_script(args)
    return run_suite(args)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
