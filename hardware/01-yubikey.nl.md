# YubiKey

🇬🇧 [English](01-yubikey.md) | 🇳🇱 Nederlands

Hardware tweefactorauthenticatie voor het homelab. De YubiKey 5C NFC is de primaire tweede factor voor Proxmox VE en wordt bij elke toekomstige foundation service uit de roadmap als eerste 2FA-methode geconfigureerd.

## Uitgangspunt

De Proxmox web UI was beveiligd met TOTP via Microsoft Authenticator. Dat werkt, maar TOTP is niet phishing-resistent. Een aanvaller die een overtuigende nep-loginpagina opzet kan de TOTP-code onderscheppen en binnen het tijdvenster van dertig seconden doorsturen naar de echte interface. WebAuthn lost dat op: de key verifieert het domein cryptografisch, dus een nep-pagina kan de challenge niet doorsturen.

De YubiKey vervangt TOTP niet. Hij komt ernaast als primaire factor. TOTP blijft als backup voor situaties waar de key niet beschikbaar is.

## Hardware

| Eigenschap | Waarde |
|------------|--------|
| Model | YubiKey 5C NFC |
| Connector | USB-C |
| NFC | Ja |
| Firmware | 5.7.4 |
| Ondersteunde protocollen | OTP, FIDO U2F, FIDO2, OATH, PIV, OpenPGP, YubiHSM Auth |

## Initiele configuratie

Na het aansluiten via USB-C:

```
ykman info          # Controleer firmware en interfaces
ykman fido access change-pin   # Stel een FIDO2 PIN in
```

De FIDO2 PIN is vereist bij elke WebAuthn-registratie en login. Bewaar de PIN in Vaultwarden zodra die draait.

## Vereisten voor WebAuthn

WebAuthn werkt niet zonder twee voorwaarden die bij een standaard Proxmox-installatie niet op orde zijn.

### Lokale DNS

WebAuthn vereist een domeinnaam als Relying Party ID. Een IP-adres werkt niet in de meeste browser-implementaties. De PVE web UI auto-fill vult het node-IP in als RP ID. Dat levert een niet-beschrijvende fout op: `failed to begin webauthn context instantiation: The configuration was invalid`.

Lokale DNS-records zijn ingesteld via de UniFi gateway (Client Devices > device > IP Settings > Local DNS Record):

| Hostname | Doel |
|----------|------|
| `srv-01.jacops.local` | PVE Node 1 |
| `srv-02.jacops.local` | PVE Node 2 |
| `pbs-01.jacops.local` | Proxmox Backup Server |

De gateway beheert de DNS-records centraal. Dat werkt voor elk apparaat op het netwerk zonder per-host configuratie. `/etc/hosts` op de Mac zou hetzelfde doen maar alleen voor de Mac zelf.

### Vertrouwd TLS-certificaat

WebAuthn vereist een vertrouwde TLS-verbinding. Het standaard PVE self-signed certificaat wordt niet door alle browsers vertrouwd op de manier die WebAuthn nodig heeft. Firefox negeert self-signed end-entity certs uit de macOS system keychain, zelfs met `security.enterprise_roots.enabled = true`. Alleen certificaten met de CA basic constraint worden geimporteerd.

De oplossing is een eigen homelab CA. De `JacOps Homelab CA` ondertekent service-certs die in alle browsers vertrouwd zijn via een enkele CA-import in de macOS system keychain. Zie [decisions](../docs/decisions.nl.md) onder "Eigen homelab CA boven self-signed certificaten" voor de volledige afweging.

**CA details:**

| Eigenschap | Waarde |
|------------|--------|
| CN | JacOps Homelab CA |
| Key | RSA 4096-bit, AES256-encrypted |
| Geldigheid | 10 jaar |
| Constraints | `CA:TRUE, pathlen:0` |
| Locatie key | `~/.homelab-ca/ca.key` (chmod 700) |

**Service-certs:**

| Eigenschap | Waarde |
|------------|--------|
| Key | RSA 2048-bit |
| Geldigheid | 2 jaar |
| SAN | `DNS:<hostname>.jacops.local` plus legacy hostname |

Het eerste service-cert is gegenereerd voor `srv-01.jacops.local`. De nodes `srv-02` en `pbs-01` volgen.

## WebAuthn-registratie bij Proxmox VE

### Datacenter-configuratie

WebAuthn Settings staan onder Datacenter > Options in de PVE web UI, of via CLI in `/etc/pve/datacenter.cfg`:

```
webauthn: id=jacops.local,origin=https://srv-01.jacops.local:8006,rp=jacops.local
```

| Veld | Waarde | Toelichting |
|------|--------|-------------|
| RP ID | `jacops.local` | Domein, niet het volledige hostname. Hierdoor werkt dezelfde registratie voor zowel `srv-01` als `srv-02` |
| Origin | `https://srv-01.jacops.local:8006` | Volledige URL inclusief poort |
| RP Name | `jacops.local` | Weergavenaam in de browser-prompt |

### Registratie

1. Login op de PVE web UI via `https://srv-01.jacops.local:8006`
2. Two Factor > Add > WebAuthn
3. Browser toont de WebAuthn-prompt
4. Voer de FIDO2 PIN in
5. Raak de YubiKey aan
6. Geef de registratie een beschrijving (bijvoorbeeld "YubiKey 5C NFC")

Na registratie zijn er twee 2FA-factoren actief:

| Factor | Type | Rol |
|--------|------|-----|
| YubiKey 5C NFC | WebAuthn/FIDO2 | Primair |
| Microsoft Authenticator | TOTP | Backup |

## Firefox-specifieke instellingen

Firefox op macOS heeft twee instellingen die WebAuthn met hardware keys beinvloeden.

### macOS passkey-handler uitschakelen

Firefox delegeert WebAuthn standaard naar de macOS passkey-handler. Die handler is ontworpen voor iCloud Keychain passkeys en werkt niet betrouwbaar met USB security keys. De macOS-dialoog toont eerst "Save a passkey?" voor iCloud, en na "More Options" > "Security Key" herkent hij de YubiKey touch niet.

In `about:config`:

```
security.webauthn.enable_macos_passkeys = false
```

Firefox gebruikt dan zijn eigen FIDO2/WebAuthn-handler die direct via USB HID met de key communiceert.

### Enterprise roots aanhouden

```
security.enterprise_roots.enabled = true
```

Deze instelling zorgt dat Firefox CA-certificaten uit de macOS system keychain importeert. Zonder deze instelling vertrouwt Firefox de homelab CA niet en blokkeert WebAuthn de registratie met een `SecurityError`.

## Geplande uitbreiding

Elke toekomstige foundation service krijgt de YubiKey als primaire 2FA-factor. De roadmap beschrijft de volgorde:

| Service | Status | Opmerking |
|---------|--------|-----------|
| Proxmox VE | Actief | WebAuthn geregistreerd voor `root@pam` |
| Proxmox Backup Server | Gepland | Wacht op CA-cert voor `pbs-01.jacops.local` |
| Vaultwarden | Gepland | WebAuthn als primaire factor, TOTP als backup |
| Forgejo | Gepland | WebAuthn na eerste user-setup |
| Bitwarden cloud | Gepland | Aparte YubiKey-slot of aparte key voor scheiding met Vaultwarden |

TOTP via Microsoft Authenticator blijft bij elke service als terugvaloptie.

## Herstelstrategie

Verlies van de YubiKey mag geen lockout veroorzaken. Drie lagen voorkomen dat:

1. **TOTP backup.** Elke service met WebAuthn heeft ook TOTP geconfigureerd. De Authenticator-app op de iPhone dient als onafhankelijke tweede factor
2. **Recovery codes.** Proxmox VE genereert recovery codes bij 2FA-registratie. Deze worden offline bewaard en verhuizen naar Vaultwarden zodra die draait
3. **Root SSH-toegang.** Bij totale lockout van de web UI kan 2FA via de CLI worden gereset op de node zelf. Dit vereist SSH-toegang met de geautoriseerde private key

## Gerelateerd

- [02-hardening.nl.md](../proxmox/02-hardening.nl.md): Fase 6 beschrijft de 2FA-configuratie in de hardening-context
- [decisions](../docs/decisions.nl.md): "Eigen homelab CA boven self-signed certificaten" voor de CA-afweging
- [lessons-learned](../docs/lessons-learned.nl.md): WebAuthn met IPs, Firefox enterprise_roots, macOS passkey-handler
