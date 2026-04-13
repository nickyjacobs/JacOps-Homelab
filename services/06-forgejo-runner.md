# Forgejo Runner

🇬🇧 English | 🇳🇱 [Nederlands](06-forgejo-runner.nl.md)

The Forgejo Runner executes CI/CD workflows for repositories on the Forgejo instance. It runs as a systemd service in its own LXC container on Node 2, with Docker as the execution backend for workflow jobs.

## Why a dedicated runner

The existing GitHub Actions workflows (link checking with lychee, secret scanning with gitleaks) run on GitHub-hosted runners. A dedicated runner on the cluster makes it possible to run the same checks locally without depending on GitHub's infrastructure. The runner lives on Node 2 to spread the workload relative to Forgejo itself (Node 1).

Forgejo Actions is compatible with the GitHub Actions workflow format. The workflows in `.forgejo/workflows/` use the same YAML syntax but replace GitHub-specific action wrappers with direct CLI tools. The `.github/workflows/` remain unchanged for GitHub.

## Architecture

```
Forgejo (CT 160, Node 1)          Runner (CT 161, Node 2)
┌─────────────────────┐           ┌──────────────────────────┐
│  Forgejo API :3000  │◄── poll ──│  forgejo-runner daemon   │
│  Actions backend    │           │  ┌────────────────────┐  │
│                     │── job ──► │  │ Docker container   │  │
│                     │           │  │ (workflow job)     │  │
│                     │◄─ logs ── │  └────────────────────┘  │
└─────────────────────┘           └──────────────────────────┘
VLAN 40 (Apps)                    VLAN 40 (Apps)
```

The runner polls the Forgejo API every two seconds for new jobs. When a trigger fires (push, schedule, workflow_dispatch), the runner starts a Docker container with the appropriate base image, clones the repository, and executes the workflow steps. Logs are sent back to Forgejo and visible in the web UI.

## Container specs

| Setting | Value |
|---------|-------|
| VMID | 161 |
| Type | LXC (unprivileged) |
| Node | Node 2 |
| OS | Debian 13 (Trixie) |
| CPU | 2 cores |
| RAM | 2048 MB |
| Swap | 512 MB |
| Disk | 15 GB on NVMe thin pool (`local-lvm`) |
| VLAN | 40 (Apps) |
| IP | Static, assigned via container configuration |
| Boot | `onboot: 1` |
| Features | `keyctl=1,nesting=1` (required for Docker-in-LXC) |
| Tags | `forgejo-runner`, `homelab` |

The rootfs lives on the NVMe thin pool. Docker image pulls and container I/O benefit from the faster storage. Both `keyctl=1` and `nesting=1` are required for Docker to run correctly in an unprivileged LXC container.

## Software

| Component | Version | Installation |
|-----------|---------|-------------|
| Docker CE | 29.4.0 | Via the official Docker APT repository |
| forgejo-runner | 12.8.2 | Binary in `/usr/local/bin/forgejo-runner`, SHA256-verified |

## Configuration

### Runner config

The runner config lives at `/var/lib/forgejo-runner/config.yml`. Registration information (token, UUID, instance URL) is stored in `/var/lib/forgejo-runner/.runner`.

| Setting | Value | Reason |
|---------|-------|--------|
| `capacity` | `1` | One job at a time, prevents resource contention |
| `NODE_EXTRA_CA_CERTS` | `/etc/ssl/certs/homelab-ca.crt` | Node.js (checkout action) trusts the homelab CA |
| `docker_host` | `automount` | Docker socket automatically mounted in job containers |
| Container options | CA cert and CA bundle volume mounts | TLS verification works in job containers |

### Labels

| Label | Docker image | Usage |
|-------|-------------|-------|
| `ubuntu-latest` | `node:20-bookworm` | Default for most workflows |
| `ubuntu-22.04` | `ubuntu:22.04` | Specific Ubuntu version |
| `debian-latest` | `debian:trixie-slim` | Lightweight Debian |

### TLS and the homelab CA

Job containers run in isolation and do not trust the homelab CA by default. Two volume mounts solve this:

- `/usr/local/share/ca-certificates/homelab-ca.crt` is mounted as `/etc/ssl/certs/homelab-ca.crt` (individual CA certificate)
- `/etc/ssl/certs/ca-certificates.crt` from the host is mounted into the container (full CA bundle including the homelab CA)

`NODE_EXTRA_CA_CERTS` tells Node.js to add the homelab CA to its trust list. This is needed for the `actions/checkout` step that clones the repository via HTTPS from Forgejo.

### Forgejo-side configuration

Actions is enabled in Forgejo's `app.ini`:

```ini
[actions]
ENABLED = true
DEFAULT_ACTIONS_URL = https://github.com
```

`DEFAULT_ACTIONS_URL` points to GitHub so that third-party actions (checkout, lychee, gitleaks) resolve directly without requiring full URLs in workflow files.

## Security

### Service user

The runner runs as a dedicated `forgejo-runner` user with membership in the `docker` group. No shell (`/usr/sbin/nologin`), home directory at `/var/lib/forgejo-runner`.

### systemd hardening

| Directive | Effect |
|-----------|--------|
| `NoNewPrivileges=true` | Prevents privilege escalation |
| `ProtectSystem=strict` | Filesystem read-only except allowed paths |
| `ProtectHome=true` | No access to /home |
| `PrivateTmp=true` | Own /tmp namespace |
| `ReadWritePaths` | Only `/var/lib/forgejo-runner` |

### Limited scope

The runner registration is instance-wide, not per-repository. The runner only executes jobs that match its labels. Docker containers for jobs are ephemeral and cleaned up after completion.

## Status: proof-of-concept

The runner is operational and tested, but runs as a proof-of-concept. The workflows in `.forgejo/workflows/` only trigger on `workflow_dispatch` (manual), not on every push. Reason: this repo is public on GitHub and the GitHub Actions workflows already cover CI fully. Running the same checks automatically on Forgejo is redundant.

The runner becomes production-relevant when:
- Private repositories land in Forgejo (configs, scripts, compose files that should not be on GitHub)
- Workflows are needed that interact with the cluster (deploy scripts, backup verification)
- The GitHub dependency is deliberately reduced

## Workflows

Two workflows are available for manual execution:

| Workflow | Purpose | Trigger |
|----------|---------|---------|
| `gitleaks.yml` | Secret scanning via gitleaks CLI | workflow_dispatch |
| `lychee.yml` | Link checking via lychee CLI | workflow_dispatch |

Trigger via the Forgejo web UI (Actions > workflow > "Run Workflow") or via the API.

The Forgejo versions live in `.forgejo/workflows/` and use CLI tools directly instead of GitHub-specific action wrappers. The `.github/workflows/` versions remain unchanged and run on GitHub.

**Differences from GitHub versions:**

- `gitleaks`: the GitHub action (v2) requires a paid license outside GitHub. The Forgejo version downloads the gitleaks binary directly
- `lychee`: the GitHub action has PATH issues in the act runner. The Forgejo version installs lychee as a binary

## Backup

CT 161 is included in the weekly PBS backup job (Sunday 03:00, four weeks retention). The runner itself is stateless at the application level: the registration file and config are the only things that need to be preserved. In case of container loss, re-registration with a new token is faster than a restore.

## Related

- [Forgejo](05-forgejo.md): the Git forge this runner belongs to
- [Roadmap](../docs/roadmap.md): Forgejo Runner is the fourth foundation service
- [Vaultwarden](04-vaultwarden.md): API token stored as `homelab/forgejo-api-token-ci-setup`
