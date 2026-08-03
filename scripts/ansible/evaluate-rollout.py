#!/usr/bin/env python3
"""Evaluate installer evidence without performing any remote operation."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


AUTH_MARKERS = (
    "auth_unavailable",
    "invalid_refresh_token",
    "token_expired",
    "no auth available",
    "invalid refresh token",
)
NOT_INSTALLED_MARKERS = ("command not found", "cli not found")
REQUIRED_PLAN_KEYS = (
    "run_base",
    "install_node",
    "install_core_apps",
    "install_extra_apps",
    "install_dingtalk",
    "fix_path",
    "repair_openclaw",
    "run_codex_cli",
    "run_cliproxy",
    "run_secrets",
    "run_cliproxy_config",
)
LEGACY_OPTIONAL_PHASES = ("doubao-config", "extra-apps")


def load_json(path: Path, required: bool = False) -> dict[str, Any]:
    if not path.exists():
        if required:
            raise SystemExit(f"Required report is missing: {path}")
        return {}
    try:
        value = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"Failed to read {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise SystemExit(f"Expected a JSON object in {path}")
    return value


def resolve_profile(version: str, arch: str) -> str | None:
    try:
        major = int(version.split(".", 1)[0])
    except (TypeError, ValueError):
        return None
    if major == 26 and arch == "arm64":
        return "macos26-arm64"
    if major == 15 and arch == "arm64":
        return "macos15-arm64"
    if major == 15 and arch == "x86_64":
        return "macos15-x64"
    if major == 14 and arch == "x86_64":
        return "macos14-x64"
    return None


def issue(code: str, message: str, *, manual: bool = False) -> dict[str, Any]:
    return {"code": code, "message": message, "manual": manual}


def validation_state(component: dict[str, Any]) -> str:
    status = str(component.get("status") or "missing")
    reason_code = str(component.get("reason_code") or "")
    error = str(component.get("error_tail") or "").lower()
    if status == "pass":
        return "pass"
    if reason_code == "auth_unavailable" or any(marker in error for marker in AUTH_MARKERS):
        return "manual_action_required"
    if reason_code == "not_installed" or any(marker in error for marker in NOT_INSTALLED_MARKERS):
        return "not_installed"
    if status in ("skipped", "missing"):
        return status
    return "fail"


def phase_is_blocking(phase: dict[str, Any]) -> bool:
    if "blocking" in phase:
        return bool(phase["blocking"])
    return phase.get("phase") not in LEGACY_OPTIONAL_PHASES


def load_final_validation(report_dir: Path) -> dict[str, Any]:
    merged = load_json(report_dir / "validation-report.json", required=True)
    for path in sorted(report_dir.glob("validation-*-report.json")):
        candidate = load_json(path)
        for component in ("codex", "openclaw"):
            value = candidate.get(component)
            if isinstance(value, dict) and value.get("status") not in (None, "skipped"):
                merged[component] = value
    return merged


def evaluate_assessment(report_dir: Path, run_id: str) -> dict[str, Any]:
    preflight = load_json(report_dir / "preflight-report.json", required=True)
    scan = load_json(report_dir / "assessment-install-report.json")
    validation = load_json(report_dir / "assessment-validation-report.json")
    blockers: list[dict[str, Any]] = []
    warnings: list[dict[str, Any]] = []

    profile = resolve_profile(str(preflight.get("macos_version", "")), str(preflight.get("arch", "")))
    if preflight.get("ssh_reached") is not True:
        blockers.append(issue("ssh_unreachable", "Target SSH preflight did not complete"))
    if preflight.get("enough_disk") is not True:
        blockers.append(issue("disk_low", "Target does not have the required free disk space"))
    if profile is None:
        blockers.append(issue("unsupported_profile", "No supported package profile matches the target"))
    if profile == "macos14-x64" and preflight.get("clt_available") is not True:
        blockers.append(
            issue(
                "clt_required",
                "macOS 14 Intel requires compatible Command Line Tools to be installed before apply",
                manual=True,
            )
        )
    if preflight.get("gui_session_active") is False:
        warnings.append(issue("gui_session", "No active GUI session; app first-run checks may need a user login", manual=True))
    if preflight.get("sudo_checked") is True and preflight.get("sudo_noninteractive_ok") is False:
        warnings.append(issue("sudo_prompt", "Apply must use a safe interactive sudo path", manual=True))

    codex = validation_state(validation.get("codex", {}))
    openclaw = validation_state(validation.get("openclaw", {}))
    if codex == "manual_action_required":
        warnings.append(issue("codex_oauth", "Existing Codex authentication requires renewal", manual=True))

    return {
        "schema_version": 1,
        "stage": "assessment",
        "run_id": run_id,
        "status": "blocked" if blockers else "ready",
        "ai_decision_required": True,
        "target": {
            "host": preflight.get("host", "unknown"),
            "macos_version": preflight.get("macos_version", "unknown"),
            "arch": preflight.get("arch", "unknown"),
        },
        "expected_profile": profile,
        "current_runtime": {"codex": codex, "openclaw": openclaw},
        "plan_reasons": scan.get("plan", {}).get("reasons", ""),
        "blockers": blockers,
        "warnings": warnings,
    }


def evaluate_final(
    report_dir: Path, run_id: str, *, allow_missing_extra_apps: bool = False
) -> dict[str, Any]:
    preflight = load_json(report_dir / "preflight-report.json", required=True)
    install = load_json(report_dir / "install-result.json", required=True)
    final_scan = load_json(report_dir / "final-install-report.json", required=True)
    validation = load_final_validation(report_dir)
    blockers: list[dict[str, Any]] = []
    optional_issues: list[dict[str, Any]] = []
    manual_actions: list[dict[str, Any]] = []

    required_phase_failures = [
        phase
        for phase in install.get("phases", [])
        if phase.get("status") == "fail" and phase_is_blocking(phase)
    ]
    optional_phase_failures = [
        phase
        for phase in install.get("phases", [])
        if phase.get("status") == "fail" and not phase_is_blocking(phase)
    ]
    install_state = "fail" if required_phase_failures else "pass"
    if required_phase_failures:
        blockers.append(issue("install_required", "One or more required install phases failed"))
    for phase in optional_phase_failures:
        code = "doubao_config" if phase.get("phase") == "doubao-config" else "optional_phase"
        optional_issues.append(issue(code, f"Optional phase failed: {phase.get('phase', 'unknown')}"))

    plan = final_scan.get("plan", {})
    required_plan_keys = REQUIRED_PLAN_KEYS
    if allow_missing_extra_apps:
        required_plan_keys = tuple(
            key
            for key in required_plan_keys
            if key not in ("install_extra_apps", "install_dingtalk")
        )
    residual = [key for key in required_plan_keys if plan.get(key) is True]
    if residual:
        blockers.append(issue("required_residual", f"Required checkpoints remain after repair: {', '.join(residual)}"))
        install_state = "fail"

    real_model = final_scan.get("cliproxy", {}).get("real_model_request")
    if real_model == "failed":
        blockers.append(issue("cliproxy_real_model", "CLIProxyAPI real model request failed"))
        install_state = "fail"

    codex = validation_state(validation.get("codex", {}))
    openclaw = validation_state(validation.get("openclaw", {}))
    if codex == "manual_action_required":
        blockers.append(issue("codex_oauth", "Codex requires interactive OAuth renewal", manual=True))
    elif codex != "pass":
        blockers.append(issue("codex_validation", f"Codex validation status is {codex}"))
    if openclaw != "pass":
        blockers.append(issue("openclaw_validation", f"OpenClaw validation status is {openclaw}"))

    manual = final_scan.get("manual_tasks", {})
    if manual.get("weixin_qr_login_is_manual") is True:
        manual_actions.append(issue("weixin_qr", "Weixin QR login is manual", manual=True))
    if manual.get("macos_tcc_permissions_are_manual") is True:
        manual_actions.append(issue("macos_tcc", "macOS TCC permissions are manual", manual=True))

    required_nonmanual = [item for item in blockers if not item["manual"]]
    required_manual = [item for item in blockers if item["manual"]]
    if required_nonmanual:
        status = "fail"
    elif required_manual:
        status = "manual_action_required"
    elif optional_issues or manual_actions:
        status = "pass_with_warnings"
    else:
        status = "pass"

    profile = resolve_profile(str(preflight.get("macos_version", "")), str(preflight.get("arch", "")))
    return {
        "schema_version": 1,
        "stage": "final",
        "run_id": run_id,
        "status": status,
        "ai_decision_required": status != "pass",
        "target": {
            "host": preflight.get("host", "unknown"),
            "macos_version": preflight.get("macos_version", "unknown"),
            "arch": preflight.get("arch", "unknown"),
        },
        "expected_profile": profile,
        "main_chain": {"install": install_state, "codex": codex, "openclaw": openclaw},
        "duration_seconds": install.get("duration_seconds"),
        "repair_attempts": max(
            int(install.get("attempt", 1)),
            max((int(phase.get("attempt", 1)) for phase in install.get("phases", [])), default=1),
        )
        - 1,
        "blockers": blockers,
        "optional_issues": optional_issues,
        "manual_actions": manual_actions,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", choices=("assessment", "final"), required=True)
    parser.add_argument("--report-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--run-id", default="")
    parser.add_argument("--allow-missing-extra-apps", action="store_true")
    args = parser.parse_args()

    run_id = args.run_id or args.report_dir.name
    result = (
        evaluate_assessment(args.report_dir, run_id)
        if args.stage == "assessment"
        else evaluate_final(
            args.report_dir,
            run_id,
            allow_missing_extra_apps=args.allow_missing_extra_apps,
        )
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(args.output)


if __name__ == "__main__":
    main()
