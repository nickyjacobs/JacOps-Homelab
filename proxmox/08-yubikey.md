# YubiKey

🇬🇧 English | 🇳🇱 [Nederlands](08-yubikey.nl.md)

Hardware two-factor authentication for the homelab. The YubiKey 5C NFC is the primary second factor for Proxmox VE and will be configured as the first 2FA method for every future foundation service on the roadmap.

## Background

The Proxmox web UI was protected with TOTP via Microsoft Authenticator. That works, but TOTP is not phishing-resistant. An attacker who sets up a convincing fake login page can intercept the TOTP code and forward it to the real interface within the thirty-second time window. WebAuthn solves this: the key verifies the domain cryptographically, so a fake page cannot relay the challenge.

The YubiKey does not replace TOTP. It sits alongside it as the primary factor. TOTP remains as a backup for situations where the key is not available.

## Hardware

| Property | Value |
|----------|-------|
| Model | YubiKey 5C NFC |
| Connector | USB-C |
| NFC | Yes |
| Firmware | 5.7.4 |
| Supported protocols | OTP, FIDO U2F, FIDO2, OATH, PIV, OpenPGP, YubiHSM Auth |

## Initial setup

After connecting via USB-C:

```
ykman info          # Check firmware and interfaces
ykman fido access change-pin   # Set a FIDO2 PIN
```

The FIDO2 PIN is required for every WebAuthn registration and login. Store the PIN in Vaultwarden once it is running.

## WebAuthn prerequisites

WebAuthn does not work without two conditions that are not met by a default Proxmox installation.

### Local DNS

WebAuthn requires a domain name as Relying Party ID. An IP address does not work in most browser implementations. The PVE web UI auto-fill populates the node IP as RP ID, which results in a non-descriptive error: `failed to begin webauthn context instantiation: The configuration was invalid`.

Local DNS records are set via the UniFi gateway (Client Devices > device > IP Settings > Local DNS Record):

| Hostname | Purpose |
|----------|---------|
| `srv-01.jacops.local` | PVE Node 1 |
| `srv-02.jacops.local` | PVE Node 2 |
| `pbs-01.jacops.local` | Proxmox Backup Server |

Central DNS was chosen over `/etc/hosts` on the Mac. The gateway is the source of truth, and the records work for any device on the network without per-host configuration.

### Trusted TLS certificate

WebAuthn requires a trusted TLS connection. The default PVE self-signed certificate is not trusted by all browsers in the way WebAuthn needs. Firefox ignores self-signed end-entity certs from the macOS system keychain, even with `security.enterprise_roots.enabled = true`. Only certificates with the CA basic constraint are imported.

The solution is a custom homelab CA. The `JacOps Homelab CA` signs service certificates that are trusted in all browsers via a single CA import into the macOS system keychain. See [decisions](../docs/decisions.md) under "Custom homelab CA over self-signed certificates" for the full rationale.

**CA details:**

| Property | Value |
|----------|-------|
| CN | JacOps Homelab CA |
| Key | RSA 4096-bit, AES256-encrypted |
| Validity | 10 years |
| Constraints | `CA:TRUE, pathlen:0` |
| Key location | `~/.homelab-ca/ca.key` (chmod 700) |

**Service certificates:**

| Property | Value |
|----------|-------|
| Key | RSA 2048-bit |
| Validity | 2 years |
| SAN | `DNS:<hostname>.jacops.local` plus legacy hostname |

The first service certificate was generated for `srv-01.jacops.local`. Nodes `srv-02` and `pbs-01` follow.

## WebAuthn registration on Proxmox VE

### Datacenter configuration

WebAuthn Settings are under Datacenter > Options in the PVE web UI, or via CLI in `/etc/pve/datacenter.cfg`:

```
webauthn: id=jacops.local,origin=https://srv-01.jacops.local:8006,rp=jacops.local
```

| Field | Value | Notes |
|-------|-------|-------|
| RP ID | `jacops.local` | Domain, not the full hostname. This allows the same registration to work for both `srv-01` and `srv-02` |
| Origin | `https://srv-01.jacops.local:8006` | Full URL including port |
| RP Name | `jacops.local` | Display name in the browser prompt |

### Registration

1. Log in to the PVE web UI via `https://srv-01.jacops.local:8006`
2. Two Factor > Add > WebAuthn
3. Browser shows the WebAuthn prompt
4. Enter the FIDO2 PIN
5. Touch the YubiKey
6. Give the registration a description (e.g. "YubiKey 5C NFC")

After registration, two 2FA factors are active:

| Factor | Type | Role |
|--------|------|------|
| YubiKey 5C NFC | WebAuthn/FIDO2 | Primary |
| Microsoft Authenticator | TOTP | Backup |

## Firefox-specific settings

Firefox on macOS has two settings that affect WebAuthn with hardware keys.

### Disable the macOS passkey handler

Firefox delegates WebAuthn by default to the macOS passkey handler. That handler is designed for iCloud Keychain passkeys and does not work reliably with USB security keys. The macOS dialog shows "Save a passkey?" for iCloud first, and after "More Options" > "Security Key" it does not recognise the YubiKey touch.

In `about:config`:

```
security.webauthn.enable_macos_passkeys = false
```

Firefox then uses its own FIDO2/WebAuthn handler that communicates directly with the key via USB HID.

### Keep enterprise roots enabled

```
security.enterprise_roots.enabled = true
```

This setting makes Firefox import CA certificates from the macOS system keychain. Without it, Firefox does not trust the homelab CA and WebAuthn blocks registration with a `SecurityError`.

## Planned expansion

The YubiKey will be configured as the primary 2FA factor for every future foundation service. The roadmap describes the order:

| Service | Status | Notes |
|---------|--------|-------|
| Proxmox VE | Active | WebAuthn registered for `root@pam` |
| Proxmox Backup Server | Planned | Awaiting CA cert for `pbs-01.jacops.local` |
| Vaultwarden | Planned | WebAuthn as primary factor, TOTP as backup |
| Forgejo | Planned | WebAuthn after initial user setup |
| Bitwarden cloud | Planned | Separate YubiKey slot or separate key for isolation from Vaultwarden |

TOTP via Microsoft Authenticator remains as a fallback for every service.

## Recovery strategy

Loss of the YubiKey must not cause a lockout. Three layers prevent that:

1. **TOTP backup.** Every service with WebAuthn also has TOTP configured. The Authenticator app on the iPhone serves as an independent second factor
2. **Recovery codes.** Proxmox VE generates recovery codes at 2FA registration. These are stored offline and will move to Vaultwarden once it is running
3. **Root SSH access.** In case of total web UI lockout, 2FA can be reset via the CLI on the node itself. This requires SSH access with the authorised private key

## Related

- [02-hardening.md](02-hardening.md) — Phase 6 describes the 2FA configuration in the hardening context
- [decisions](../docs/decisions.md) — "Custom homelab CA over self-signed certificates" for the CA rationale
- [lessons-learned](../docs/lessons-learned.md) — WebAuthn with IPs, Firefox enterprise_roots, macOS passkey handler
