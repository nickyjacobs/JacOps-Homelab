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

Ten services together form the foundation layer that all future work builds on. The order is binding: each deploy in this list protects or supports the next one.

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

**4. Forgejo Runner**

CT 161 on Node 2, Debian 13 base, two cores, 2 GB RAM, 15 GB rootfs on the NVMe thin pool. LXC features `keyctl=1,nesting=1` for Docker-in-LXC. Docker CE 29.4.0 and forgejo-runner v12.8.2 as a systemd service with sandbox directives. Dedicated `forgejo-runner` service user with Docker group membership.

Registered as `homelab-runner` with the Forgejo instance on CT 160, with labels `ubuntu-latest`, `ubuntu-22.04` and `debian-latest`. Two Forgejo-specific workflows in `.forgejo/workflows/` run as a shadow-run alongside the existing GitHub Actions: gitleaks (secret scanning) and lychee (link checking). The Forgejo versions use CLI tools directly because the GitHub action wrappers are not compatible with the Forgejo runner (gitleaks requires a paid license, lychee has PATH issues).

The homelab CA is trusted in the container and made available to Docker job containers via volume mounts. `NODE_EXTRA_CA_CERTS` ensures the checkout action can clone the repository via HTTPS. Actions is enabled in Forgejo's app.ini with `DEFAULT_ACTIONS_URL = https://github.com` so that third-party actions resolve directly.

Debian 13 instead of the planned Debian 12 for consistency with the Forgejo container. The runner lives on Node 2 instead of Node 1 to spread workload.

Full documentation in [services/06-forgejo-runner.md](../services/06-forgejo-runner.md).

**5. Miniflux**

CT 163 on Node 1, Debian 13 base, one core, 512 MB RAM, 5 GB rootfs on the NVMe thin pool. Docker compose with `miniflux/miniflux:2.2.6`, `postgres:16-alpine` and `caddy:2.11.2-alpine`, all three pinned on tag plus SHA256 digest. Caddy as reverse proxy with homelab CA cert. Internal-only through `miniflux.jacops.local`.

Debian 13 instead of the planned Debian 12 because only that template was available. RAM increased from 256 MB to 512 MB and disk from 3 GB to 5 GB because Miniflux, PostgreSQL, Caddy and the Docker daemon together need more overhead. See [decisions.md](decisions.md) for the reasoning.

19 feeds across three categories. Threat Intel (7 feeds): SANS ISC, Microsoft Security Blog, Unit 42, CrowdStrike, Krebs on Security, The DFIR Report, BleepingComputer. Advisories (2 feeds): Debian Security Advisories (DSA) and PostgreSQL News. Releases (10 feeds): Vaultwarden, ntfy, Uptime Kuma, n8n, Miniflux, Caddy, Forgejo, Docker/Moby, Docker Compose and WireGuard. Feed selection based on signal-to-noise ratio; Rapid7 and Cloudflare Blog were removed after evaluation due to excessive marketing.

ntfy integration configured with a dedicated publish token and internal endpoint. API key created for future n8n integration. Uptime Kuma monitor on the `/healthcheck` endpoint.

Full documentation in [services/07-miniflux.md](../services/07-miniflux.md).

**6. step-ca**

CT 164 on Node 1, Debian 13 base, one core, 512 MB RAM, 5 GB rootfs on the NVMe thin pool. step-ca v0.30.2 as internal ACME server with two-tier PKI. Root CA offline on USB drive, intermediate CA as software key on the LXC (JWE-encrypted). EC P-256 for the entire chain. ACME provisioner with 72-hour default cert lifetime and tls-alpn-01 challenge.

The original decision specified the intermediate key on YubiKey PIV slot 9c. During implementation this turned out to be incompatible with automatic ACME certificate issuance: the YubiKey would need to sit in the server 24/7 and would no longer be available for WebAuthn. Software intermediate key is the standard industry approach. See [decisions.md](decisions.md) for the reasoning.

Full documentation in [services/08-step-ca.md](../services/08-step-ca.md).

**7. Traefik**

CT 165 on Node 1, Debian 13 base, one core, 512 MB RAM, 5 GB rootfs on the NVMe thin pool. Traefik v3.6.13 as central reverse proxy for all foundation services. Replaces the per-LXC Caddy setups on Vaultwarden (CT 152), Forgejo (CT 160) and Miniflux (CT 163).

Automatic ACME certificates via step-ca with 72-hour lifetime. Global security headers (HSTS, nosniff, frameDeny) at the entrypoint level. Dashboard secured with basicAuth and IP allowlist. Backend traffic is unencrypted HTTP on the same VLAN, locked down with iptables rules per backend LXC (DOCKER-USER chain for Docker services, INPUT chain for native services).

DNS records for all proxied services (miniflux, forgejo, vault) point to the Traefik IP via UniFi DNS policies.

Full documentation in [services/09-traefik.md](../services/09-traefik.md).

**8. Beszel**

Beszel v0.18.7 as a Docker container in CT 151 alongside Uptime Kuma, ntfy and cloudflared. Image pinned on tag plus SHA256 digest. Hub on port 8090, internally reachable via `beszel.jacops.local` behind Traefik with an automatic step-ca certificate.

Nine agents installed: seven foundation LXCs (CT 151, 152, 160, 161, 163, 164, 165) via SSH mode on port 45876, two PVE nodes (srv-01, srv-02) via WebSocket mode with per-system tokens connecting directly to the hub. The PVE nodes required a targeted UniFi firewall rule (Servers to Apps, device-based, port 8090 TCP) because the zone firewall blocks cross-VLAN traffic by default.

Backend firewall on CT 151: DOCKER-USER chain with ACCEPT for the PVE node IPs and Traefik, DROP for everything else. Alerting via ntfy (Shoutrrr) with thresholds on CPU, RAM and disk (80%, 10 minutes) plus status alerts on all nine systems.

Full documentation in [services/10-beszel.md](../services/10-beszel.md).

### Coming up (order binding)

**9. Dockge**

In CT 150 alongside the existing n8n compose stack, under 100 MB RAM. Compose UI for all Docker stacks running on the same daemon. Internal-only through `dockge.jacops.local`. This replaces the manual `docker compose` work for Vaultwarden, Miniflux and any later compose-based service.

**10. ccusage**

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
5. During the evening session of 2026-04-13, the Forgejo Runner was deployed on CT 161 (Node 2). Docker CE and forgejo-runner v12.8.2 with two shadow-run workflows (gitleaks, lychee). Actions enabled in Forgejo. Debian 13 for consistency.
6. During the session of 2026-04-14, Miniflux v2.2.6 was deployed on CT 163 (Node 1). Docker Compose with PostgreSQL 16 and Caddy. 19 feeds in three categories. ntfy integration and Uptime Kuma monitor. RAM and disk increased from roadmap spec. Architecture decisions made: Traefik as standard reverse proxy (replacing Caddy), step-ca as internal ACME server (replacing manual OpenSSL CA).
7. During the session of 2026-04-15, step-ca v0.30.2 (CT 164) and Traefik v3.6.13 (CT 165) were deployed. Two-tier PKI with offline root key on USB and software intermediate key (YubiKey PIV dropped due to incompatibility with automatic ACME). Caddy removed from CT 152, 160 and 163. Backend firewalling with iptables per LXC. Three services migrated to central Traefik with automatic step-ca certificates (72-hour lifetime).
8. During the session of 2026-04-16, Beszel v0.18.7 was deployed in CT 151. Nine agents: seven LXCs via SSH mode, two PVE nodes via WebSocket mode with a targeted cross-VLAN firewall rule. Universal token rejected in favour of manual per-system registration. ntfy alerting and Uptime Kuma monitor configured.
