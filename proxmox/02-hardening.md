# Hardening

🇬🇧 English | 🇳🇱 [Nederlands](02-hardening.nl.md)

This document describes the security hardening applied to the Proxmox cluster. The work was done in nine phases over a single session. Each phase targets a specific attack surface.

## Starting point

The cluster was functional but not hardened. The initial audit found:

- Root SSH login with password authentication enabled
- No brute-force protection (fail2ban not installed)
- Proxmox firewall disabled on both nodes
- No two-factor authentication on the web interface
- Security updates weeks behind (including OpenSSH and OpenSSL)
- Kernel-level network hardening absent (ICMP redirects accepted)
- Unnecessary services running (rpcbind, postfix)
- No automated backups configured
- No automatic security patching

None of these are unusual for a freshly installed Proxmox cluster. The defaults prioritize accessibility over security. This document describes what changed and why.

## Phase 1: System updates

Both nodes were updated to the latest packages, including a kernel upgrade and Proxmox version alignment. Before the update, one node was two minor versions behind the other. After the update both run the same Proxmox and kernel version.

The update included security patches for OpenSSH, OpenSSL, corosync and several other packages. A coordinated reboot of both nodes followed to activate the new kernel.

Application containers are set to `onboot: 1` so they restart automatically after a reboot. This was not configured before and meant services stayed down until someone noticed.

## Phase 2: SSH hardening

Three changes reduce the SSH attack surface.

**Dedicated admin user.** A non-root user with sudo access replaces direct root login for daily operations. Root login is restricted to public key authentication only (`PermitRootLogin prohibit-password`). This means an attacker who steals the root password cannot SSH in. They would need the private key file.

**Key-only authentication.** Password authentication is disabled entirely (`PasswordAuthentication no`). This eliminates brute-force attacks against SSH as a category. The only way in is possessing an authorized private key.

**Reduced exposure.** X11 forwarding is off (unnecessary attack surface), maximum authentication attempts are capped at three per connection, and idle sessions disconnect after five minutes without activity.

```
# /etc/ssh/sshd_config.d/hardening.conf
PermitRootLogin prohibit-password
PasswordAuthentication no
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
```

## Phase 3: Brute-force protection

Fail2ban monitors authentication logs and temporarily bans IP addresses after repeated failures.

**SSH jail.** Five failed login attempts within ten minutes trigger a one-hour ban. With key-only authentication already in place, this jail catches port scanners and bots that try regardless.

**Proxmox web UI jail.** The same logic applied to the Proxmox API daemon. Five failed web UI login attempts from the same IP result in a one-hour ban. The filter watches journald for pvedaemon authentication failure messages.

```ini
# /etc/fail2ban/jail.d/proxmox.conf
[proxmox]
enabled = true
port = 8006
filter = proxmox
backend = systemd
maxretry = 5
bantime = 3600
findtime = 600
```

## Phase 4: Proxmox firewall

Proxmox has its own firewall layer that runs on each node, independent of the network firewall on the gateway. Enabling it adds defense in depth: even if the network firewall is misconfigured, the hypervisor still drops unauthorized traffic.

The cluster-wide policy is set to `DROP` for inbound traffic. Outbound traffic is allowed (nodes need to reach package repositories and the internet for updates).

Allowed inbound traffic:

| Source | Destination | Protocol | Port | Purpose |
|--------|-------------|----------|------|---------|
| Management VLAN | Nodes | TCP | 22 | SSH access |
| Management VLAN | Nodes | TCP | 8006 | Web UI access |
| VPN subnet | Nodes | TCP | 22, 8006 | Remote administration |
| Servers VLAN | Nodes | Any | Any | Inter-node cluster traffic |
| Apps VLAN | Nodes | TCP | 8006 | Monitoring health checks |
| Apps VLAN | Nodes | ICMP | - | Monitoring ping checks |

Everything else is silently dropped. A device on the Lab or IoT VLAN cannot reach the Proxmox management interface even if the network firewall fails to block it.

## Phase 5: Kernel hardening

Sysctl settings harden the network stack against common attacks.

| Setting | Value | Purpose |
|---------|-------|---------|
| `accept_redirects` | 0 (IPv4 + IPv6) | Prevents ICMP redirect attacks that reroute traffic |
| `send_redirects` | 0 | Node should not redirect other hosts |
| `tcp_syncookies` | 1 | SYN flood protection |
| `log_martians` | 1 | Logs packets with impossible source addresses |
| `icmp_echo_ignore_broadcasts` | 1 | Ignores broadcast pings (smurf attack mitigation) |
| `icmp_ignore_bogus_error_responses` | 1 | Ignores malformed ICMP error messages |
| `rp_filter` | 2 (loose) | Reverse path filtering, loose mode for Proxmox compatibility |

These settings are stored in `/etc/sysctl.d/99-hardening.conf` and survive reboots.

## Phase 6: Two-factor authentication

TOTP is enabled for the root account on the Proxmox web UI. Logging in requires both the password and a six-digit code from an authenticator app. This protects against credential theft: a stolen password alone is not enough to access the management interface.

Recovery codes are stored offline in case the authenticator device is lost.

## Phase 7: Service cleanup

Two unnecessary services were disabled.

**rpcbind** listens on port 111 on all interfaces. It is a prerequisite for NFS, which the cluster does not use. Leaving it running exposes an unnecessary network service. Disabled on both nodes.

**postfix** was running as a local mail transport agent. The cluster does not send email notifications. No other service depends on local mail delivery. Disabled on both nodes.

## Phase 8: Automated backups

A scheduled backup job runs weekly on Sunday at 03:00. It uses snapshot mode so running containers are not interrupted.

| Setting | Value |
|---------|-------|
| Schedule | Sunday 03:00 |
| Storage | Bulk HDD on Node 1 |
| Compression | zstd |
| Retention | 4 weekly backups |
| Scope | All VMs and containers |

The backup covers configuration recovery and accidental deletion. The four-week window means there is always a known-good snapshot to roll back to.

## Phase 9: Automatic security patching

Unattended-upgrades is installed and configured to automatically apply Debian security patches. Proxmox-specific updates are excluded from automatic installation because they can introduce breaking changes that need manual review.

```
Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${distro_codename}-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
```

Automatic reboots are disabled. Security patches that require a reboot (kernel updates) are applied manually during a maintenance window.

## Result

After all nine phases, the cluster has:

- Key-only SSH with a dedicated admin user
- Brute-force protection on SSH and the web interface
- A host-level firewall with deny-by-default policy
- Hardened kernel network settings
- Two-factor authentication on the management interface
- No unnecessary services listening
- Automated weekly backups with four-week retention
- Automatic Debian security patching

These controls stack with the network-level defences described in the [network section](../network/). The combination means an attacker has to bypass the zone-based firewall, the host-level firewall, key-based SSH authentication, and TOTP-protected web authentication before reaching anything useful.
