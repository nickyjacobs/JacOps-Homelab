# Roadmap

🇬🇧 English | 🇳🇱 [Nederlands](roadmap.nl.md)

Living master document for the homelab plan. This describes where we are, what the next steps are, and which explicit choices have already been made. Changes to this plan are documented in [decisions.md](decisions.md) and back-references in this file are updated.

The roadmap is split into four phases. Phases can run in parallel when they do not block each other, but the order within a phase is binding unless explicitly changed.

## Principles

These agreements drive every deploy:

- **Everything internal through WireGuard.** No new public Cloudflare tunnels for foundation services. n8n and Uptime Kuma keep their existing tunnels because those were already in place with a concrete external use case.
- **Zero secrets in the public repo.** Tokens, passwords, fingerprints and internal IPs are replaced by placeholders before any commit reaches main.
- **Pin container images to tag plus SHA256 digest.** No `latest` tags. Upgrades are deliberate actions.
- **Security-first defaults.** Every service gets a dedicated service account with scoped ACLs, 2FA where possible, audit logs enabled. Root accounts are never used for daily operations.
- **Hardware 2FA through a YubiKey 5C NFC.** From availability the YubiKey becomes the primary second factor for Vaultwarden, Bitwarden cloud, Proxmox VE and Forgejo. TOTP through Microsoft Authenticator remains as backup and recovery path.
- **Break circular dependencies.** Every service that would protect itself gets an alternative recovery path. PBS is the first example.
- **Discipline on credentials.** Once Vaultwarden is running, every new credential from every deploy goes straight into it. No paper notes, no text files on hosts.
- **Blue team tooling paused until after eJPT.** No parallel security-tooling learning during the eJPT sprint. Velociraptor and everything that comes with it only goes live after 17 May 2026.

## Phase 0: finish hardening and docs

The Proxmox cluster was already in good shape on the network and host-hardening side. This phase closes the remaining gaps and syncs the documentation with reality.

### Done

- SSH hardening on both nodes: `PermitRootLogin prohibit-password`, `PasswordAuthentication no`, `X11Forwarding no`, `MaxAuthTries 3`, `ClientAliveInterval 300`, `ClientAliveCountMax 2`. `sshd -t` for validation and `systemctl reload ssh` so existing sessions did not break.
- `sudo` installed on both nodes. The admin user `nicky` was added to the `sudo` group with a NOPASSWD sudoers entry so daily operations do not block on a missing password.
- The n8n compose (CT 150) now has explicit tag plus SHA256 digest pinning for all three containers: `n8n 2.13.4`, `postgres:16.13-alpine`, `cloudflared:2026.3.0`. The `latest` tags that were there before are gone.
- The first manual `vzdump` plus restore test was run on CT 151 (the monitoring stack). The backup was restored to a throwaway CT 199, the config was verified, and the test CT was cleaned up. This was needed because the scheduled weekly job had never actually run before.
- Seven small `apt` updates on both nodes (acme, access-control, widget-toolkit, i18n, nvidia-vgpu, yew-mobile). No reboot needed.
- `vm.swappiness=10` added to `/etc/sysctl.d/99-hardening.conf`. `SystemMaxUse=500M` in `journald.conf` to bound journal growth.
- Proxmox Backup Server fully deployed including datastore, ACLs, backup jobs and maintenance schedules. See [03-backups.md](../proxmox/03-backups.md) for all the details.

### Open

- Nine firewall tests from the network improvement plan (verify cross-VLAN allow and deny from the Windows lab VM, Mac on the Management VLAN, and iPhone over 4G plus WireGuard).
- Additional Proxmox docs in this repo for storage details, networking (VLAN-aware bridge), VM hygiene (guest agent, protection flags, tags) and monitoring. Not urgent because `03-backups` already closed the biggest gap.

## Phase 1: foundation deployments

Eight services together form the foundation layer that all future work builds on. The order is binding: each deploy in this list protects or supports the next one.

### Done

**1. Proxmox Backup Server (PBS)**

VM 180 `pbs-01` on Node 1. Two vCPUs, 4 GB RAM, 32 GB OS disk on the NVMe thin pool, 500 GB datastore as a qcow2 on the SATA directory. Dedicated service account `pve-sync@pbs` with an API token plus `DatastoreBackup` ACL scoped to `/datastore/main`. Two backup jobs together resolve the circular dependency: `weekly-backup` for all VMs and containers to PBS (Sunday 03:00, four weeks retention, VM 180 excluded) and `pbs-self-backup` for VM 180 only to the old SATA directory (Monday 04:00, two weeks retention). Datastore maintenance runs in a Sunday window shortly after the backup: garbage collection 05:00, prune 05:30, verify 06:00. Full writeup in [03-backups.md](../proxmox/03-backups.md).

**2. Vaultwarden**

CT 152 on Node 1, Debian 13 base, one core, 512 MB RAM, 5 GB rootfs on the NVMe thin pool. Docker compose with Vaultwarden 1.35.4 and Caddy 2.11.2-alpine, both pinned to tag plus SHA256 digest. Caddy as reverse proxy on the same LXC with a certificate signed by the homelab CA. Internal-only through `vault.jacops.local`, only reachable through WireGuard or the local network. Admin token as an Argon2id hash in env vars, `SIGNUPS_ALLOWED=false`, `INVITATIONS_ALLOWED=false`, `DISABLE_ICON_DOWNLOAD=true` as an SSRF mitigation, `PASSWORD_ITERATIONS=600000` for extra KDF cost.

Two-factor through the YubiKey 5C NFC as passkey (primary) and 2FAS Auth as TOTP backup. Master password as a diceware passphrase of at least twenty characters.

Datastore backups run through the weekly PBS backup job. Two additional paths are planned: daily through `restic` to PBS, and weekly as encrypted tar through `age` to an external Backblaze B2 bucket. Renovate or a manual update cycle monitors new Vaultwarden releases and keeps the container within a week of every security patch.

Full documentation in [services/04-vaultwarden.md](../services/04-vaultwarden.md).

**3. Forgejo v11 LTS**

CT 160 on Node 1, Debian 13 base, two cores, 1 GB RAM, 20 GB rootfs on the SATA directory. Binary install (Forgejo 11.0.12, no Docker), SQLite database, systemd service with sandbox directives (NoNewPrivileges, ProtectSystem=strict, PrivateTmp, PrivateDevices). Caddy 2.11.2 as reverse proxy on the same LXC with security headers (HSTS, X-Frame-Options, nosniff). Internal-only through `forgejo.jacops.local`, TLS via homelab CA. Built-in SSH server on port 2222 to avoid a conflict with the runner.

Security hardening in app.ini: registration disabled, sign-in required for all pages, git hooks disabled (RCE mitigation), SSRF surface restricted (webhooks private hosts only, mirrors off, packages off, mailer off). Admin credentials stored directly in Vaultwarden. 2FA through YubiKey as WebAuthn passkey (primary) and 2FAS Auth as TOTP backup.

Debian 13 instead of the planned Debian 12 because only that template was available on the node. Forgejo is a Go binary and is distro-independent. Nesting enabled for systemd 257 in unprivileged LXC, not for Docker.

Full documentation in [services/05-forgejo.md](../services/05-forgejo.md).

### Coming up (order binding)

**4. Forgejo Runner**

CT 161 on Node 2, Debian 12 base, two cores, 2 GB RAM, 15 GB rootfs on the NVMe thin pool. LXC features `keyctl=1,nesting=1` to get Docker inside LXC working. `act_runner` binary, registered against the Forgejo instance from step 3. First workload: a shadow run of `weekly_refresh.yml` alongside the existing GitHub Actions, until four successful runs prove the migration is reliable. Then the GitHub Actions side is disabled.

The runner lives on Node 2 instead of Node 1 to spread workload. Docker-in-LXC needs some extra nesting permissions, deliberately limited to this one LXC.

**5. Miniflux**

CT 163 on Node 1, Debian 12 base, one core, 256 MB RAM, 3 GB rootfs on the NVMe thin pool. Docker compose with `miniflux/miniflux:2.2.x` and `postgres:16-alpine`, both pinned on digest. Internal-only through `miniflux.jacops.local`.

Initial feed list focuses on security sources: NVD JSON feed, CISA KEV feed, Rapid7 release notes, Microsoft MSRC, HashiCorp security advisories, Cloudflare security blog, Mandiant, CrowdStrike, Unit42, SANS ISC, plus the GitHub release feeds for the services we run ourselves (PBS, Forgejo, Vaultwarden, ntfy, Uptime Kuma, n8n). An n8n workflow polls the Miniflux API daily and pushes high-severity new entries into a `/threat-intel` note in Obsidian and as a ntfy alert to the phone.

**6. Beszel hub plus agents**

Hub in CT 151 alongside the existing monitoring stack, under 50 MB RAM total for hub and all agents combined. Agents as a Go binary on both PVE nodes plus all new foundation LXCs. Internal-only through `beszel.jacops.local`.

Uptime Kuma keeps doing reachability, Beszel adds host metrics (CPU, RAM, disk, network). The two do not overlap.

**7. Dockge**

In CT 150 alongside the existing n8n compose stack, under 100 MB RAM. Compose UI for all Docker stacks running on the same daemon. Internal-only through `dockge.jacops.local`. This replaces the manual `docker compose` work for Vaultwarden, Miniflux and any later compose-based service.

**8. ccusage**

On the MacBook through `bun install -g ccusage`. Zero infra on the cluster. Reads Claude Code's own JSONL session logs in `~/.claude/projects/` and shows per-session, per-day and per-model costs. Statusline hook in `~/.claude/settings.json` gives live budget visibility during work.

This replaces the LiteLLM proxy from earlier plan versions. Reason: LiteLLM's supply chain compromise in March 2026, a cluster of critical CVEs in Q1 2026, and cache_control regressions with Claude Code v2.0.76+. See [decisions.md](decisions.md) for the full reasoning.

### Outside the cluster

**Bitwarden cloud free tier**

Migrate personal credentials (banking, social media, email, subscriptions) out of Keeper into Bitwarden cloud. No self-host because Bitwarden has a dedicated security team and Cure53 audits that a solo-operated Vaultwarden instance cannot match for the category of credentials that sit at the identity-disaster level.

YubiKey 5C NFC as primary 2FA, a hardware factor separate from Vaultwarden's YubiKey so a lost device does not compromise both vaults (or a single YubiKey with two slots if that is more practical at availability).

**Keeper**

Stays in use for a limited work context, out of scope for this repo. No personal or homelab items remain in Keeper, so the lock-in stays limited to what already sits inside the work context.

**TryHackMe Premium + HTB Starting Point**

TryHackMe Premium for the duration of the eJPT prep (fourteen dollars per month). The Jr Penetration Tester path is the target, not random rooms. HTB Starting Point free tier as supplemental boxes for pattern recognition.

## Phase 2: eJPT practice stack

Parallel with Phase 1, but only these three components. The stack from earlier plan versions (Juice Shop, BBOT, ProjectDiscovery stack, Vulhub, GOAD) was cut after the validation round against the eJPT v2 update from 26 March 2026.

| Component | Location | Purpose |
|-----------|----------|---------|
| Docker host LXC | CT 170 on Node 1, Lab VLAN 30 | Isolated container runner for practice targets |
| DVWA | Container in CT 170 | Web vulns: SQLi, XSS, command injection, file upload, CMS and WordPress exploitation (new in the eJPT v2 update) |
| Metasploitable 2 | Container or VM in CT 170 | MSFconsole workflow, host enumeration, classic exploit modules |
| Windows 10 Evaluation | VM on Node 2 | Local privesc with winPEAS, Microsoft 90-day free eval ISO |

Every component in this stack shows up directly in passing blogs from 2024 through 2026. Everything not in those blogs is cut.

The exam is on 15 or 16 May 2026. The sprint runs from 11 April, roughly 34 days. Study schedule details are out of scope for this roadmap and live in personal planning.

## Phase 3: after eJPT, from 17 May 2026

Blue team and red team tooling comes online from 17 May, with Velociraptor first because it offers direct transfer value to SOC work in general, and to Rapid7-based environments specifically.

| # | Service | Location | Reason |
|---|---------|----------|--------|
| 1 | Velociraptor | Server as LXC plus agents on target lab | Open source DFIR agent, Rapid7-acquired, learn VQL, direct transfer value to SOC work |
| 2 | Wazuh (lightweight, 4 GB RAM) | LXC or VM | Alternative SIEM alongside Rapid7, SCA, FIM, vulnerability scanning |
| 3 | MISP | LXC | Threat intel platform with community feeds |
| 4 | DFIR-IRIS | LXC | Case management, replacement for TheHive 5 after it went commercial |
| 5 | Sliver C2 | LXC in Lab VLAN 30 | Open source C2 for OSEP preparation |
| 6 | GOAD-MINILAB through Ludus | Rotation on Node 2 | AD pentest baseline with Ludus as orchestrator |
| 7 | SysReptor | LXC | Reporting engine for JacOps, custom templates |

Parallel to these, local on the MacBook stays: Atomic Red Team, Sigma-CLI, YARA-X and Chainsaw for purple team exercises. These tools ask for no server resources.

## Skiplist: explicitly not deploying

These services were cut after critical validation. They are listed here so a later session does not accidentally suggest them again.

| What | Reason |
|------|--------|
| LiteLLM | Supply chain compromise in March 2026 on PyPI v1.82.7 and v1.82.8, critical CVEs in Q1 2026 (OIDC auth bypass, privilege escalation, SQL injection), cache_control regressions with Claude Code v2.0.76+, no workable per-skill tracking due to environment variable limitations. Replaced by `ccusage`. |
| Apprise | ntfy v2.14 and v2.15 now have declarative users, ACLs, tokens and templates. No concrete use case left that Apprise solves. |
| Changedetection.io | Three recent CVEs (SSRF, auth bypass, XSS). Most security feeds already ship RSS, Miniflux is lighter and safer. |
| Juice Shop | OSWE and bug bounty territory, not eJPT according to recent passing blogs. |
| Metasploitable 3 | Frustrating to deploy through Packer/Vagrant, no benefit over Metasploitable 2 for eJPT scope. |
| BBOT | Bug bounty recon framework, eJPT asks for simple nmap plus service enumeration. |
| ProjectDiscovery stack (nuclei, httpx, subfinder, dnsx) | Same reasoning, bug bounty tooling. |
| Vulhub rotation | CVE-specific labs, eJPT tests workflow not CVE knowledge. |
| GOAD, BadBlood, Vulnerable-AD for eJPT | Multiple 2026 passing blogs confirm there is no AD on the eJPT exam. |
| Homarr, Homepage | Nice-to-have dashboards, not foundation. |
| Authentik, Authelia | SSO broker only valuable at five or more web UIs with heavy login. Currently YAGNI. |
| Temporal, Apache Airflow, Prefect | Workflow orchestration overkill, n8n covers it. |
| Helicone, Langfuse, Qdrant | LLM observability and vector DB overkill without a central LLM proxy. |
| OpenCTI | Needs 16 GB RAM for a stable single-node deploy. Too heavy on this hardware. |
| Security Onion 2 | Needs 200 GB disk and 8 to 24 GB RAM. Too heavy. |
| Nextcloud, Jellyfin, Pi-hole, AdGuard | Not career-relevant, other tools cover the use cases. |
| Ollama on Proxmox without GPU | Too slow for usable LLM inference, model choice stays Claude via API. |
| CyberChef self-hosted | Offline tool, no server deploy needed. |
| OpenVAS and GVM | Resource hog, Nuclei CLI covers vulnerability scanning at homelab scale. |
| Public Cloudflare tunnels for new foundation services | Everything internal through WireGuard. |

## History of this roadmap

The plan was adjusted three times during the 2026-04-11 session:

1. After the first research round with three parallel agents, there was an expanded but unfiltered foundation layer plus a broad eJPT stack.
2. After a critical validation round with three new agents on foundation services, eJPT stack and LiteLLM specifically, LiteLLM, Apprise and Changedetection.io were cut and the eJPT stack was shortened.
3. During the deploy session of 2026-04-11, PBS was fully installed and Vaultwarden and Forgejo swapped order so that credentials land directly in a vault instead of temporarily on hosts.
4. During the deploy session of 2026-04-13, Forgejo v11.0.12 LTS was deployed on CT 160 with security hardening (systemd sandbox, SSRF restriction, git hooks disabled). Debian 13 instead of Debian 12 due to template availability.
