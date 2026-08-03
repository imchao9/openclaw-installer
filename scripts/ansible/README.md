# OpenClaw fleet rollout

Ansible is the fleet orchestration layer. The single-machine source of truth is
still `install-openclaw.sh` / `install-new-macbook.sh`.

The recommended flow is:

```text
bootstrap-clt -> preflight -> scan -> sync -> install missing -> validate -> final scan -> collect reports
```

`macOS 14.x + x86_64` resolves to `macos14-x64`. This profile requires
compatible Command Line Tools to be present before apply and bundles only
Intel-compatible Codex, Clash Party, DingTalk, and CLIProxyAPI assets. See
[`docs/INTEL_MACOS14_SETUP.md`](../../docs/INTEL_MACOS14_SETUP.md).

For normal machine-by-machine delivery, prefer the mechanical two-boundary runner instead of invoking each playbook interactively:

```bash
RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')"

bash scripts/ansible/mechanical-rollout.sh assess \
  -i /tmp/openclaw-inventory.ini \
  --run-id "$RUN_ID"

# AI or a human reviews mechanical-assessment-summary.json exactly once here.

bash scripts/ansible/mechanical-rollout.sh apply \
  -i /tmp/openclaw-inventory.ini \
  --run-id "$RUN_ID" \
  --approve-assessment \
  --private-secrets \
  --extra-apps \
  --prompt-sudo-password
```

The apply boundary is deterministic: profile gate, CLT bootstrap, profile-specific sync, install, one targeted repair pass, validation, final scan, and report collection.
It does not call AI between phases.
See `docs/mechanical-rollout.md` for report semantics, exit codes, credential handling, and rerun behavior.

`bootstrap-clt` uses raw SSH, so it can run before Python-backed Ansible modules
work on a fresh macOS install. It detects the remote architecture with
the remote macOS version first: macOS 15.x receives
`Command_Line_Tools_for_Xcode_16.4.dmg`; macOS 26.2+ then uses `uname -m` so
`arm64` targets receive `Command_Line_Tools_26.5_Apple_silicon.dmg` when
available, and Intel or fallback targets receive
`upload-packages/source-assets/openclaw-team/Command_Line_Tools_26.5_Universal.dmg`.

`private-secrets/ips.txt` contains secrets. Do not use it directly as inventory. Generate an
inventory that contains IP addresses only:

```bash
ANSIBLE_USER=mac bash scripts/ansible/ips-to-inventory.sh private-secrets/ips.txt > /tmp/openclaw-inventory.ini
```

If your target machines use another login user, replace `mac` with that user.

## Full rollout

Public package only:

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/rollout.yml --ask-pass
```

With private config/auth material:

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/rollout.yml \
  -e sync_private_secrets=1 \
  --ask-pass
```

This runs CLT bootstrap first, then preflight, scans every machine, syncs the
package, generates `reports/install-plan.env`, runs only the missing selected
phases, validates, then fetches JSON reports under `scripts/ansible/reports/<host>/`.

Summarize fetched reports:

```bash
bash scripts/ansible/summarize-reports.sh
```

The summary includes four execution columns:

- `preflight`: `ok`, `disk_low`, `sudo_prompt`, or `no_report`.
- `install`: status from `install-result.json`.
- `codex_val`: Codex model smoke-test status from `validation-report.json`.
- `openclaw_val`: OpenClaw model smoke-test status from `validation-report.json`.

When a row is not enough, inspect:

- `preflight-report.json`: SSH reachability, macOS, architecture, disk, sudo,
  and GUI session state.
- `install-result.json`: selected phases, exit codes, and the last 80 log lines
  per phase.
- `validation-report.json`: validation status, exit code, proxy usage, and error
  tails.
- `post-install-report.json` / `final-install-report.json`: final checkpoint
  state and remaining plan.

## Step-by-step mode

Bootstrap Command Line Tools only:

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/bootstrap-clt.yml \
  --ask-pass --ask-become-pass
```

Preflight only:

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/preflight.yml \
  --ask-pass
```

Initial read-only scan:

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/scan.yml \
  -e scan_label=initial \
  --ask-pass
```

Sync the current package:

```bash
PORT=8765 bash scripts/serve-package-http.sh

OPENCLAW_PACKAGE_BASE_URL=http://<installer-host-ip>:8765 \
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/sync.yml \
  -e sync_private_secrets=1 \
  --ask-pass
```

When `OPENCLAW_PACKAGE_BASE_URL` is set, `sync.yml` downloads
`openclaw-layer-index.json`, selects the common, architecture, and CLT layers for
the detected profile, resumes each layer with `curl -C -`, verifies SHA-256, and
assembles the normal single install directory on the target. Without the URL,
the rsync path assembles the same layers locally before synchronization.

Install only missing checkpoints:

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/install-missing.yml \
  --ask-pass
```

Install missing non-core apps as well:

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/install-missing.yml \
  -e install_extra_apps=1 \
  --ask-pass
```

Fetch reports without running more install steps:

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/collect-reports.yml \
  --ask-pass
```

Validate only, without installing:

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/validate-agents.yml \
  --ask-pass
```

Validate only Codex:

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/validate-agents.yml \
  -e validate_openclaw=0 \
  --ask-pass
```

Validate only OpenClaw:

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/validate-agents.yml \
  -e validate_codex=0 \
  --ask-pass
```

Exact-match model acceptance:

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/validate-agents.yml \
  -e expected_text=HELLO_OK \
  -e codex_validation_mode=exec \
  -e codex_hello_prompt='Reply with exactly HELLO_OK' \
  -e openclaw_hello_prompt='Reply with exactly HELLO_OK' \
  --ask-pass
```

## Single-machine phase commands

On a target machine that already has `~/openclaw-installer-run/`:

```bash
# Read-only checkpoint scan
bash ~/openclaw-installer-run/install-files/installer-core/scripts/check-install-checkpoints.sh \
  --run-dir ~/openclaw-installer-run

cd ~/openclaw-installer-run/install-files

# Install public/base software
INSTALL_PHASE=base bash install-new-macbook.sh

# Install non-core apps only
INSTALL_PHASE=extras bash install-new-macbook.sh

# Restore private config and auth material
PRIVATE_SECRETS_DIR=../private-secrets INSTALL_PHASE=secrets bash install-new-macbook.sh

# Repair Codex CLI only
INSTALL_PHASE=codex-cli bash install-new-macbook.sh

# Install/start CLIProxyAPI only
INSTALL_PHASE=cliproxy bash install-new-macbook.sh

# Point Codex/OpenClaw at local CLIProxyAPI only
INSTALL_PHASE=cliproxy-config bash install-new-macbook.sh

# Add DeepSeek fallback only
INSTALL_PHASE=deepseek bash install-new-macbook.sh

# Install office/data-analysis skills only
INSTALL_PHASE=office-skills bash install-new-macbook.sh

# Validate model calls only
INSTALL_PHASE=validate bash install-new-macbook.sh
```

Unified wrapper options:

```bash
cd ~/openclaw-installer-run
bash install-openclaw.sh --skip-validate
bash install-openclaw.sh --skip-base
bash install-openclaw.sh --skip-secrets
INSTALL_PHASE=cliproxy-config bash install-new-macbook.sh
bash install-openclaw.sh --with-weixin
```

## Checkpoint model

`installer-core/scripts/check-install-checkpoints.sh` writes:

- `install-report.json`: machine state
- `install-plan.env`: safe shell variables consumed by the install playbook

The current checkpoints cover:

- preflight: macOS, arch, disk
- package layout: `install-openclaw.sh`, `install-files/`, `private-secrets/`
- secrets manifest: whether Codex auth/config, OpenClaw config, CLIProxy auth,
  DeepSeek key, Clash profiles, and media secrets are present in
  `private-secrets/`
- commands: `node`, `npm`, `codex`, `openclaw`, PATH profiles
- apps: Chrome, Codex, OpenClaw, Obsidian, Clash Party, DingTalk, AweSun, Doubao input
  and Doubao input-source/microphone configuration
- configs: Codex, OpenClaw, media secrets, CLIProxy model wiring
- CLIProxyAPI: binary, config, LaunchAgent, and port 8317 listener
- Clash: profiles, process, socks 7890
- manual flags: missing secrets and Clash GUI startup needs

The generated plan keeps `PLAN_RUN_BASE` for compatibility, but also emits
finer-grained install intents:

- `PLAN_INSTALL_NODE`
- `PLAN_INSTALL_CORE_APPS`
- `PLAN_INSTALL_DINGTALK`
- `PLAN_FIX_PATH`
- `PLAN_REPAIR_OPENCLAW`
- `PLAN_CONFIGURE_DOUBAO`

`install-missing.yml` consumes those finer flags first, so a missing PATH or
DingTalk no longer forces the entire base phase to rerun.

Some states cannot be solved by SSH automation. They should remain explicit
report states:

- `needs_manual_clash_gui`: Clash Party is installed/configured, but GUI launch
  or first-run state is required.
- `needs_secrets`: the public package is present, but private auth/key material
  was not synced.
- Weixin QR login and non-Doubao macOS TCC permissions are manual by design.
  Doubao microphone permission is configured by `PLAN_CONFIGURE_DOUBAO`.

Repair `codex: command not found` on all machines:

```bash
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/repair-codex-cli.yml
```

If npm global install needs sudo:

```bash
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/repair-codex-cli.yml \
  -e install_codex_with_become=1 \
  --ask-become-pass
```

Validate Codex and OpenClaw replies:

```bash
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/validate-agents.yml
```

The validation playbook defaults to read-only smoke checks: it does not repair
OpenClaw config and it skips the strict `cliproxy`/`deepseek` config-shape
check. To enable the strict config-shape check:

```bash
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/validate-agents.yml \
  -e check_openclaw_config_shape=1
```

To allow config repair during validation:

```bash
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/validate-agents.yml \
  -e check_openclaw_config_shape=1 \
  -e repair_openclaw_config=1
```

Validate only Codex:

```bash
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/validate-agents.yml \
  -e validate_openclaw=0
```

Validate only OpenClaw:

```bash
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/validate-agents.yml \
  -e validate_codex=0
```

Specify an OpenClaw model explicitly:

```bash
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/validate-agents.yml \
  -e openclaw_test_model=cliproxy/gpt-5.6-terra
```

If SSH password auth is needed:

```bash
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/validate-agents.yml --ask-pass
```

The default smoke prompt is `你好你是谁`. Set `expected_text` for exact-match
checks, for example:

```bash
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/validate-agents.yml \
  -e expected_text=HELLO_OK \
  -e codex_hello_prompt='Reply with exactly HELLO_OK' \
  -e openclaw_hello_prompt='Reply with exactly HELLO_OK'
```
