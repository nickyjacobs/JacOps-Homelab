# Design Decisions

🇬🇧 English | 🇳🇱 [Nederlands](decisions.nl.md)

This document records the non-obvious choices made during the build. Each entry explains what was decided, why, and what alternatives were considered. If I rebuild this setup a year from now, these notes should prevent me from making the same mistakes or second-guessing choices that already proved correct.

---

## Custom zones over global deny-all

**Date:** 2026-04-07
**Area:** Firewall

UniFi offers two paths to deny-by-default firewalling. The first is flipping the global Default Security Posture from "Allow All" to "Block All." The second is moving every network into a custom zone, which makes inter-zone traffic deny-by-default automatically.

I chose custom zones. The global toggle is a single switch that blocks everything at once. One missed allow rule and you lock yourself out of the gateway. Custom zones achieve the same result but let you build policies per zone pair. The mental model is cleaner: each zone pair is either explicitly allowed or silently dropped.

**Trade-off:** more initial setup (13 custom policies instead of one toggle), but safer rollout and easier to reason about later.

## Apps VLAN separated from Servers

**Date:** 2026-04-07
**Area:** Segmentation

Proxmox hypervisors sit on the Servers VLAN. Application workloads (workflow automation, monitoring) sit on a separate Apps VLAN. The hypervisors can reach the Apps subnet for container management, but not the other way around.

The reason is blast radius. If an application container gets compromised, the attacker lands in the Apps zone. From there, the zone firewall blocks lateral movement to the hypervisor management plane. Without this separation, a compromised container on the same VLAN as Proxmox could attempt API calls against the hypervisor directly.

## Tagged VLAN management for Proxmox

**Date:** 2026-04-07
**Area:** Proxmox networking

Two options existed for putting Proxmox on its own VLAN. The first was changing the switch port to a native (untagged) VLAN, which requires no changes on the Proxmox side. The second was keeping the trunk port and creating a tagged sub-interface (`vmbr0.10`) on the bridge.

I went with the tagged approach. It is consistent with how VMs and containers already get their VLAN tags, it keeps the switch port as a clean trunk, and it means the Proxmox host participates in the same VLAN-aware bridge as everything else. The untagged approach would have worked but creates an inconsistency: the host uses native VLAN while its workloads use tagged VLANs on the same bridge.

## VLAN numbering matches third octet

**Date:** 2026-04-06
**Area:** Segmentation

Every VLAN ID matches the third octet of its subnet. VLAN 10 uses `10.0.10.0/24`, VLAN 30 uses `10.0.30.0/24`, and so on. This removes one layer of mental translation when troubleshooting. If you see traffic from `10.0.20.x`, you know it is VLAN 20 without checking a table.

The original setup had inconsistent numbering (VLAN 133 on `10.0.10.0`, VLAN 5 on `10.0.5.0`). Renumbering required careful sequencing because subnets had to be freed before they could be reassigned. See [lessons-learned.md](lessons-learned.md) for the details.

## WireGuard with split and full tunnel profiles

**Date:** 2026-04-07
**Area:** Remote access

Two client profiles exist. The phone uses a full tunnel that routes all traffic through the homelab, useful on untrusted WiFi. The laptop uses a split tunnel that only routes the homelab subnet through VPN, so regular browsing stays on the local connection.

WireGuard was chosen over the built-in Teleport feature. Teleport works but is vendor-locked, does not support split tunneling, and adds latency through relay servers. WireGuard is a direct peer-to-peer connection, faster, and portable to any client platform. Teleport stays enabled as a fallback for situations where UDP 51820 is blocked.

VPN clients can reach Management, Servers and Apps zones. Access to SOC, Lab and IoT is blocked. If VPN credentials leak, the attacker can reach admin interfaces but not the intentionally vulnerable lab machines or IoT devices.

## Dynamic DNS through gateway API

**Date:** 2026-04-07
**Area:** Remote access

The ISP assigns a dynamic public IP. The VPN endpoint hostname points to this IP through dynamic DNS. Instead of running a separate DDNS client, the gateway updates the DNS record directly through the DNS provider API whenever the IP changes.

The API token is scoped to a single zone with only DNS edit permissions. If the token leaks, the worst case is someone pointing the VPN hostname elsewhere. They cannot modify other DNS records, access other API resources, or intercept traffic (WireGuard authenticates peers by public key, not by hostname).

## IPS in block mode from day one

**Date:** 2026-04-06
**Area:** Hardening

The IPS was running in notify-only mode. I switched it to notify-and-block with all signature categories at maximum sensitivity.

Running IPS in notify-only mode in a homelab makes little sense. There is no SOC team watching alerts around the clock, so notifications without automatic blocking just create a log nobody reads. In a production environment you would start with notify to avoid false positives disrupting business. In a homelab, a false positive blocking something is a learning opportunity, not a business risk.

## GeoIP blocking inbound only

**Date:** 2026-04-06
**Area:** Hardening

GeoIP rules block inbound traffic from Russia, China, North Korea and Iran. Outbound is not blocked.

Blocking outbound by country is brittle. CDNs serve content from unexpected regions, package mirrors might resolve to blocked countries, and legitimate services use infrastructure globally. The value of outbound GeoIP blocking is low compared to the troubleshooting cost when something silently breaks. Inbound blocking makes more sense because there is no reason for unsolicited connections from these regions to reach a homelab.

## Encrypted DNS with filtering

**Date:** 2026-04-06
**Area:** Hardening

DNS queries go through encrypted resolvers with built-in malware and phishing filtering. Two providers are configured for redundancy.

Plain DNS leaks every domain lookup to the ISP. Encrypted DNS with filtering adds two layers: privacy (ISP cannot see queries) and basic protection (known malicious domains are blocked at the resolver level). This is not a replacement for proper endpoint security, but it catches low-hanging fruit at the network level with zero maintenance.

## Self-hosted push notifications over third-party services

**Date:** 2026-04-11
**Area:** Monitoring

Uptime Kuma supports a long list of notification providers out of the box: Telegram, Discord, Slack, email, ntfy, and more. The easy path is to pick Telegram or Discord, set up a bot, paste the token, and move on. I went with self-hosted ntfy instead.

Every monitoring alert carries the hostname, IP or URL of a service in the homelab. Sending that stream through someone else's messaging infrastructure means a third party now has a reliable view of which services run here and when they break. For a homelab that is built around security-first defaults, that felt like the wrong direction for the sake of five minutes of setup time.

ntfy runs as a container alongside Uptime Kuma. It is lightweight (around 30-50 MB of RAM), open source, and supports iOS push through an upstream pattern where the public `ntfy.sh` instance only sees a SHA256 hash of the topic and the message ID. The actual alert content stays inside the homelab because the phone fetches the message body directly from the self-hosted server after being woken up by Apple's push service.

The trade-off is added complexity: one more container, one more config file, one more troubleshooting path. The iOS push pipeline has edge cases that do not show up with a public ntfy.sh topic (see [lessons-learned.md](lessons-learned.md)). For a homelab the extra work is worth it.

## One Cloudflare tunnel per stack, multiple hostnames

**Date:** 2026-04-11
**Area:** Remote access

n8n runs with its own Cloudflared container inside the n8n stack. The monitoring stack (Uptime Kuma plus ntfy) needed public access too, and I considered three patterns:

1. Give each service its own tunnel (two tunnels for two services in the same stack)
2. Use Uptime Kuma's built-in tunnel for Uptime Kuma and add a separate tunnel for ntfy
3. Run a single standalone cloudflared container in the monitoring stack that routes both services through one tunnel with two hostnames

I picked option three. Uptime Kuma and ntfy share a failure domain: they live in the same LXC, the same Docker network, the same host. Splitting them into two tunnels would not improve resilience because a crashed LXC takes both down anyway. One tunnel with multiple public hostnames is simpler to operate, uses fewer resources, and keeps all tunnel configuration in the Cloudflare dashboard under one record.

The built-in Uptime Kuma tunnel support stays unused for the same reason. A standalone cloudflared container is language-agnostic, handles multiple hostnames natively, and has its lifecycle managed by Docker Compose instead of by the Uptime Kuma process.

The pattern is: one tunnel per stack, one stack per LXC. n8n has its tunnel, the monitoring stack has its tunnel, and any future stack (Wazuh plus whatever pairs with it) gets its own.

## Public status page without internal services

**Date:** 2026-04-11
**Area:** Monitoring

Uptime Kuma's public status page is a nice portfolio touch. It shows that services are up, it looks professional, and it mirrors what real SaaS products expose at `status.something.com`. The question was what to put on it.

The first instinct was "everything". All ten monitors, grouped by label, visible to anyone who finds the URL. The problem with "everything" is that it is a free OSINT sheet. Listing Proxmox nodes tells an attacker what hypervisor runs the infrastructure. Listing UniFi hardware tells them the network vendor. None of this is actionable on its own, but each data point narrows the guessing game if somebody decides to look harder.

The second instinct was to lock the page entirely behind Cloudflare Access or a password. Cloudflare Access breaks the iOS ntfy app because native apps cannot complete the Access login flow. Uptime Kuma 2.x removed its built-in status page password. So full lockdown would have meant either breaking iOS notifications or dropping the status page entirely.

The chosen path is a public page with a curated monitor list. Only the services that are meant to face outside are shown: n8n, ntfy, and Uptime Kuma itself. Everything internal (Proxmox, UniFi, DNS, local container checks) is visible to the admin through the dashboard after login, but invisible to the public page. The portfolio value is preserved and the OSINT surface stays small.

## Pin container images to tag plus SHA256 digest

**Date:** 2026-04-11
**Area:** Supply chain

The n8n compose stack was running with floating `latest` tags on all three containers: n8n itself, Postgres, and cloudflared. That is the default in most quickstarts and works fine until it does not. An image publisher that accidentally ships a breaking change, or an upstream that gets compromised, ends up inside your production as soon as somebody runs `docker compose pull`.

The choice was to pin each image to both the human-readable tag and the SHA256 digest of the exact image running at that moment. The format becomes `repo:tag@sha256:hash`. The tag stays readable for anyone opening the config later, the digest is cryptographic: even if somebody overwrites the tag upstream, this image reference still points to the exact image that was tested.

The effect is that upgrades become deliberate actions. Trying a new n8n version requires explicitly updating the digest, running a pull, and redeploying. No silent jump to a version I have not tested. For a homelab moving toward a client-rollout pattern, this is the right habit.

The tradeoff is slightly more work at every upgrade in exchange for predictability. I accept that.

## Proxmox Backup Server as a VM on the hypervisor

**Date:** 2026-04-11
**Area:** Backup infrastructure

The official Proxmox recommendation is that PBS runs on physically separated hardware. In a homelab with two PVE nodes and no third machine, that recommendation falls away. I faced three options: no PBS (and stay with vzdump), PBS on an external VPS over WireGuard, or PBS as a VM on one of the PVE hosts itself.

Skipping PBS means giving up deduplication, verify jobs, incremental-forever, and encryption-at-rest. Those are exactly the things that distinguish modern backup infrastructure from "putting a tar file somewhere". For a setup moving toward client work, learning the PBS flow is more valuable than keeping the simplicity of vzdump.

PBS on an external VPS restores physical separation but moves all backup data outside the local network. That costs bandwidth, requires remote encryption key handling, and makes restore operations slower. For a homelab at this scale, the extra complexity does not offset the physical separation gain.

The chosen route is PBS as a VM on Node 1, with an explicit solution for the circular dependency this introduces. The VM writes its datastore as a qcow2 file on the SATA directory, and a second backup job runs every Monday at 04:00 that takes the PBS VM itself via vzdump to that same SATA directory. On catastrophic loss of the PBS VM, it can be restored from the vzdump snapshot, after which the datastore (which lives in a separate qcow2 file on the same disk) remains intact.

The price is a second backup job and a documentation burden: the recovery procedure for PBS itself does not run through PBS. As long as Job 2 runs every Monday and notification-on-failure is enabled, that path stays visible.

## ext4 over ZFS for a single-disk PBS datastore

**Date:** 2026-04-11
**Area:** Backup infrastructure

The PBS installer asks which filesystem the datastore should use. ZFS is the canonical recommendation because it natively offers compression, checksums, and snapshots. On a single virtual disk the biggest ZFS advantage disappears: there is no redundancy between disks, so checksums can detect corruption but cannot heal it.

The ZFS ARC cache asks for roughly 1 GB of extra RAM by default. On a PBS VM that is already tight at 4 GB, that is a meaningful tax with no direct benefit. PBS runs its own deduplication and chunk hashing at the application layer, so filesystem compression does not stack in a useful way on top of what PBS already does.

ext4 became the choice. The redundancy layer sits one level up: the qcow2 file housing the datastore is covered by the `pbs-self-backup` job, and filesystem corruption is caught by fsck on boot plus the `verify-new=true` setting that checks every new backup right after upload.

If the PBS VM ever migrates to dedicated hardware with multiple disks, ZFS becomes the right choice. At this scale the simplicity of ext4 is the better trade-off.

## API token over password for PVE-PBS integration

**Date:** 2026-04-11
**Area:** Backup infrastructure

PVE can reach PBS with either a username plus password or an API token. The `pvesm add pbs` flow supports both. A password for `root@pam` is the fastest route: two lines of config and you have a connection.

The API token route takes more steps but pays itself back. The flow is: create a dedicated service account (`pve-sync@pbs`), scope DatastoreBackup permissions to `/datastore/main`, generate a token under that account, set the same DatastoreBackup role on the token explicitly, and paste the token value into the PVE storage config.

Three advantages against one disadvantage. The first advantage is revocation granularity: if the token leaks, you revoke that one token and the rest of the authentication stays intact. A leaked root password on the other hand requires rotation across all systems that use it. The second advantage is scope: the token only has backup rights on one datastore, no admin rights on other parts of PBS. The third advantage is that the service account password never needs to be used by a human. It stays a random generated value that nobody remembers and that is in no script.

The disadvantage is first-setup complexity. Two ACL entries instead of one, and a generate-token step. At every subsequent interaction with this path the token system is easier because it requires no human memory.

## Foundation layer revisited after validation round

**Date:** 2026-04-11
**Area:** Service selection

The first plan for the foundation layer listed Forgejo, Vaultwarden, LiteLLM, Apprise, and Changedetection.io as the five "must-have" services for the next expansion round. A deep validation round cast doubt on three of those five.

**LiteLLM was dropped.** In March 2026 two PyPI versions of LiteLLM were compromised through a backdoor in the CI/CD pipeline. Shortly after, a series of critical CVEs followed, including an OIDC auth bypass and a privilege escalation. For a solo Claude Code user, LiteLLM mainly offers central cost tracking and virtual keys per skill. Both turned out less sharp than expected: virtual keys require each skill to run in a separate process context, which breaks the workflow. The alternative `ccusage` reads Claude Code's own JSONL session logs directly and gives 90% of the cost-tracking value without any extra infrastructure. The trade-off between a central proxy with an active supply-chain history and a read-only tool that adds nothing to the attack surface tipped toward the second.

**Apprise was dropped.** The assumption was that Apprise as a universal notification abstraction would be valuable. On closer inspection ntfy (already running) now has declarative users, ACLs, tokens and templates. The use cases Apprise would solve are solvable with direct webhooks or the ntfy CLI. No concrete pain to solve, so no reason to add a service.

**Changedetection.io was replaced with Miniflux.** The original use case was bringing CVE feeds and vendor advisories into the threat-intel workflow. Changedetection.io has had three noteworthy CVEs in the past six months, including an SSRF and an auth bypass through decorator ordering. The bigger problem is that almost all relevant security feeds (NVD, CISA KEV, Rapid7 blog, vendor PSIRTs, GitHub releases) already ship RSS or Atom. A dedicated RSS reader like Miniflux is lighter, has a smaller attack surface, and covers the use case better. Changedetection.io remains relevant for pages without RSS, but as a foundation service it is the wrong pick.

The results were folded back into the list: Forgejo and Vaultwarden stayed, PBS was added as the critical first deploy before any other service lands, Miniflux replaced Changedetection.io, and Beszel plus Dockge joined as a lightweight host-metrics and compose-management layer.

The lesson from this round is that a service list built from a handful of blog recommendations is not the same as a validated stack. Every service that arrives is a new attack surface and a new operational burden. The question "what breaks without it" is stricter than "what would be nice to have", and that stricter question filtered three of the five original picks out.

## Skip Prometheus for now

**Date:** 2026-04-11
**Area:** Monitoring

Prometheus plus Grafana is the obvious next step in monitoring maturity. Better metrics, better dashboards, alerting rules with real logic. The homelab is not ready for it yet, and may not be ready for a while.

For ten monitors, Uptime Kuma's own dashboard answers the question that matters: is it up or not. Prometheus would add a second daemon, a scrape config, a time-series database, Grafana on top for visualization, and exporters on every host that needs deeper metrics. That is multiple hours of setup and another 500+ MB of RAM for a result that does not materially improve the "is it up" answer.

Prometheus becomes worthwhile when there are multiple data sources to correlate. Once Wazuh comes in after the eJPT certification, there will be defensive-tool data to cross-reference with availability and performance metrics. Grafana as a single pane over Uptime Kuma, Wazuh, Proxmox node-exporter and n8n starts to earn its keep at that point.

Uptime Kuma already exposes a native `/metrics` endpoint in Prometheus format, so the upgrade path is clean. No migration, no rewrite, just a new scrape target.

## Audit Round 1: accept git history with BLOCKER content (Option 3 hybrid)

**Date:** 2026-04-12
**Area:** Security, git hygiene

The first full audit of the repo found three BLOCKERs in HEAD: a concrete host IP in lessons-learned that was not written as a placeholder, an absolute filesystem path in CLAUDE.md that revealed the local directory layout, and employer references in the roadmap. All three also live in git history (commits `361f433`, `7033ebc`, `e2ca3a6`) already pushed to `origin/main`.

Three options were considered:

1. **Accept history, fix HEAD only.** No history rewrite. HEAD is clean, commits retain the leak in their diff
2. **Filter-repo plus force-push.** Cleans history, but breaks the commit-policy no-force-push rule, breaks potential clones, and GitHub cached commit views persist for months via SHA URLs
3. **Hybrid: fix HEAD now, defer history decision.** Combines the acute fix with deferral of the destructive operation

Option 3 (hybrid) was chosen. Reasoning:

- The commit-policy is a self-imposed hard rule. Breaking it requires a deliberate, documented exception, not an audit side-effect
- The repo is new, likely zero forks or clones, so the practical impact of the history leak is minimal
- The BLOCKERs have been public since the push. A few more hours of exposure does not change the risk profile
- The HEAD fix prevents further spread to new clones or scrapers
- Filter-repo can still be applied later as a deliberate, separate cleanup action

HEAD fixes applied: the IP was replaced with a placeholder, the absolute path was moved to the gitignored `CLAUDE.local.md`, and the employer references were rewritten to neutral wording. Hooks were extended with absolute-path detection to prevent recurrence.

Open: if the repo grows significantly in visibility (forks, stars), reconsider Option 2 as a controlled cleanup with an explicit commit-policy exception.

## Homelab CA over self-signed certificates

**Date:** 2026-04-12
**Area:** TLS, certificate management

Proxmox VE generates a self-signed certificate at install time using the node hostname as CN. When WebAuthn registration of a YubiKey required the PVE web UI to be accessed via a hostname instead of an IP address, a chain reaction followed: the self-signed cert had the wrong CN, Firefox did not trust it via the macOS system keychain (because `security.enterprise_roots.enabled` only imports CA certificates, not individual end-entity certs), and Chrome trusted it but that did not solve the Firefox problem.

Three options were considered:

1. **Per-service self-signed cert with correct SAN.** Works in Chrome and Safari via the system keychain, but not in Firefox without manual security exceptions per site
2. **Manually import certs into Firefox.** Works, but does not scale to multiple services and needs repeating on every cert renewal
3. **Create a homelab CA and sign all service certs with it.** The CA goes into the macOS system keychain once, after which all browsers (including Firefox via enterprise_roots) automatically trust every cert signed by it

Option 3 was chosen. The `JacOps Homelab CA` is an RSA 4096-bit root CA with `basicConstraints: CA:TRUE, pathlen:0` and a ten-year validity period. The private key is AES256-encrypted and stored in `~/.homelab-ca/` on the Mac (chmod 700). Service certs are RSA 2048-bit with two-year validity.

The immediate benefit is that every new service (Vaultwarden/Caddy, Forgejo, PBS, Miniflux) gets a cert that is trusted in all browsers without extra steps. The CA key will move to Vaultwarden once it is deployed, so the secret does not remain on an unencrypted filesystem.
