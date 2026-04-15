# step-ca

🇬🇧 [English](08-step-ca.md) | 🇳🇱 Nederlands

step-ca is de interne ACME server van het homelab. Alle services die TLS nodig hebben vragen hun certificaten hier aan via het standaard ACME protocol, met kortstondige certs die automatisch vernieuwen. Het draait als native binary in een LXC-container, intern bereikbaar via `step-ca.jacops.local`.

## Waarom een eigen ACME server

De handmatige OpenSSL CA die eerder in gebruik was (RSA 4096, twee jaar geldigheid per cert) had drie problemen. Een gecompromitteerde service-key gaf een aanvaller twee jaar geldige impersonatie. Handmatige cert-vernieuwing schaalt niet bij twintig services. En er was geen mechanisme om een gecompromitteerd cert in te trekken.

step-ca lost alle drie op. Leaf certs zijn standaard 72 uur geldig en vernieuwen automatisch. Een gestolen cert is binnen drie dagen waardeloos. Revocatie is passief: kortstondige certs verlopen simpelweg. En de ACME provisioner laat Traefik en andere clients certs aanvragen zonder handmatig tussenwerk.

Let's Encrypt was geen optie voor intern verkeer. Certificate Transparency logs onthullen interne domeinnamen, en het introduceert een externe dependency voor verkeer dat het cluster nooit verlaat.

Zie [decisions.nl.md](../docs/decisions.nl.md) onder "step-ca als interne ACME server" voor de volledige afweging.

## Architectuur

```
ACME Client ─── HTTPS ──► step-ca (ACME server) ──► BadgerDB
(Traefik)                 :8443                     (cert state)
                          Intermediate CA key
                          (EC P-256, JWE encrypted)

                LXC Container (CT 164)
                ┌──────────────────────────────────────┐
                │  step-ca v0.30.2                     │
                │  ├─ ACME provisioner                 │
                │  ├─ Intermediate cert + key           │
                │  └─ Root cert (no root key!)         │
                └──────────────────────────────────────┘
                VLAN 40 (Apps)

Offline: USB-drive CA-ROOT
         ├─ Root CA cert + key (encrypted)
         └─ Intermediate key backup (encrypted)
```

step-ca luistert op poort 8443 en beantwoordt ACME-verzoeken van clients in het netwerk. De intermediate CA key staat op de LXC zelf, versleuteld met JWE. De root CA key staat niet op de LXC. Die leeft offline op een USB-drive en wordt alleen aangesloten bij het aanmaken of vernieuwen van de intermediate.

Geen publieke tunnel, geen Cloudflare. De service is alleen bereikbaar via het lokale netwerk of WireGuard.

## Container specs

| Instelling | Waarde |
|------------|--------|
| VMID | 164 |
| Type | LXC (unprivileged) |
| Node | Node 1 |
| OS | Debian 13 (Trixie) |
| CPU | 1 core |
| RAM | 512 MB |
| Swap | 256 MB |
| Disk | 5 GB op NVMe thin pool (`local-lvm`) |
| VLAN | 40 (Apps) |
| IP | Statisch, toegewezen via containerconfiguratie |
| Boot | `onboot: 1` |
| Firewall | 1 |
| Features | `nesting=1` |
| Tags | `foundation`, `pki`, `step-ca` |

## Software

| Component | Versie | Installatie |
|-----------|--------|-------------|
| step-ca | v0.30.2 | Smallstep apt repo (standaard package) |

Geinstalleerd via de officiele Smallstep apt repository. Het standaard package volstaat; de CGO/HSM-variant is niet nodig omdat de intermediate key als software key op het filesystem staat.

## PKI

### Two-tier opzet

step-ca draait een two-tier PKI: een offline root CA en een online intermediate CA. De root ondertekent alleen de intermediate. De intermediate ondertekent alle leaf certs die clients aanvragen.

| Laag | Sleuteltype | Geldigheid | Locatie |
|------|-------------|------------|---------|
| Root CA | EC P-256 | 10 jaar | Offline op USB-drive CA-ROOT (FAT32) |
| Intermediate CA | EC P-256 | 5 jaar | CT 164, JWE-versleuteld op disk |
| Leaf certs | EC P-256 | 72 uur default, 168 uur max | Gegenereerd door ACME clients |

EC P-256 is de standaard van step-ca en biedt de breedste compatibiliteit met ACME clients, browsers en TLS-libraries.

### Root CA

De root key leeft op een USB-drive met label CA-ROOT (FAT32). De drive wordt alleen aangesloten op de LXC wanneer de intermediate vernieuwd of opnieuw ondertekend moet worden. De rest van de tijd ligt de drive fysiek in een afgesloten opslag.

Een backup van de root key staat in Vaultwarden als `homelab/step-ca-root-key-passphrase` (de passphrase) en de key zelf op een tweede USB-drive op een andere fysieke locatie.

### Intermediate CA

De intermediate key staat op CT 164 in de step-ca configuratiemap. Het bestand is versleuteld met JWE (PBES2-HS256+A128KW / A256GCM). Bij het starten van step-ca wordt het wachtwoord gelezen uit `/etc/step-ca/password.txt` (chmod 600, eigenaar `step`).

Een backup van de intermediate key leeft op dezelfde USB-drive als de root key, plus in de wekelijkse PBS backup van de container.

### Sleutelversleuteling

Alle private keys (root en intermediate) zijn versleuteld met JWE. Het encryptieschema is PBES2-HS256+A128KW voor key wrapping en A256GCM voor content encryption. Dit is de standaard van step-ca's `step crypto` tooling.

De passphrases staan in Vaultwarden:

| Secret | Vaultwarden pad |
|--------|-----------------|
| Root key passphrase | `homelab/step-ca-root-key-passphrase` |
| Intermediate key passphrase | `homelab/step-ca-intermediate-key-passphrase` |

## ACME provisioner

step-ca is geconfigureerd met een ACME provisioner die het `tls-alpn-01` challenge type ondersteunt. Clients bewijzen domeinbezit door een zelfondertekend cert met een specifieke ALPN-extensie aan te bieden op poort 443 van het aangevraagde domein.

| Instelling | Waarde |
|------------|--------|
| Provisioner type | ACME |
| Challenge | `tls-alpn-01` |
| Default cert lifetime | 72 uur |
| Max cert lifetime | 168 uur |

72 uur als standaard geeft voldoende marge voor een mislukte renewal (de meeste ACME clients vernieuwen bij twee derde van de levensduur, dus na 48 uur). 168 uur als maximum voorkomt dat een client per ongeluk langlevende certs aanvraagt.

## Waarom software key in plaats van YubiKey

Het oorspronkelijke plan was de intermediate key op de YubiKey PIV slot 9c te plaatsen (non-exportable, signing vereist fysieke YubiKey plus PIN). In de praktijk is dat niet compatibel met geautomatiseerde ACME cert-uitgifte: elke signing-operatie zou fysieke interactie vereisen. Bij twintig services die elk om de 48 uur vernieuwen is dat niet werkbaar.

De software key met JWE-encryptie is het compromis. De key staat versleuteld op disk en wordt bij startup ontgrendeld. De trade-off is dat een aanvaller met root-toegang tot CT 164 de ontgrendelde key uit het geheugen kan lezen. De mitigatie is systemd-hardening, beperkte netwerktoegang en monitoring via de wekelijkse PBS backup die een ongewijzigde baseline biedt.

## Security

### systemd hardening

step-ca draait als dedicated `step` user met een strikte systemd unit:

| Directive | Waarde |
|-----------|--------|
| `Type` | `notify` (sd_notify support sinds v0.29.0) |
| `User` | `step` |
| `NoNewPrivileges` | `true` |
| `ProtectSystem` | `full` |
| `ProtectHome` | `true` |
| `PrivateTmp` | `true` |
| `PrivateDevices` | `true` |
| `MemoryDenyWriteExecute` | `true` |

### Bestandspermissies

| Pad | Permissies | Eigenaar |
|-----|-----------|----------|
| `/etc/step-ca/` | 700 | `step:step` |
| `/etc/step-ca/password.txt` | 600 | `step:step` |
| Intermediate key | 600 | `step:step` |
| Root cert (publiek) | 644 | `root:root` |

De root cert is het enige publiek leesbare bestand. Clients hebben dit nodig om de certificaatketen te verifieren.

### Passieve revocatie

step-ca draait geen CRL of OCSP responder. Met een maximale levensduur van 168 uur voor leaf certs is actieve revocatie overbodig. Een gecompromitteerd cert verliest binnen drie tot zeven dagen zijn geldigheid. Dit is hetzelfde model dat cloud PKI-systemen zoals Google Certificate Authority Service hanteren voor kortstondige workload-certificaten.

## Toegang

| Pad | Doel |
|-----|------|
| `https://step-ca.jacops.local:8443/acme/acme/directory` | ACME directory endpoint |
| `https://step-ca.jacops.local:8443/health` | Health check |

Beide zijn alleen bereikbaar via het lokale netwerk of WireGuard. Er is geen publieke URL en geen web UI. Beheer gaat via de `step` CLI op de LXC zelf.

## Backup

De container is opgenomen in de wekelijkse PBS backup job (zondag 03:00, vier weken retentie). Dit vangt het volledige container-bestandssysteem inclusief de intermediate key, de step-ca configuratie en de BadgerDB state.

De root key leeft offline op USB en valt buiten de PBS backup. Het herstelpad voor de root key is de tweede USB-drive op een andere fysieke locatie plus de passphrase in Vaultwarden.

## Migratie van de handmatige CA

De bestaande `JacOps Homelab CA` (RSA 4096, handmatige OpenSSL workflow) blijft vertrouwd in de macOS system keychain totdat alle services zijn gemigreerd naar step-ca. De migratievolgorde per service is: Traefik configureren met de step-ca ACME endpoint, cert renewal afwachten, oud cert verwijderen. Na de laatste migratie wordt de oude CA uit de trust store verwijderd.

## Gerelateerd

- [roadmap](../docs/roadmap.nl.md): step-ca is onderdeel van de Fase 1 foundation
- [decisions](../docs/decisions.nl.md): "step-ca als interne ACME server, handmatige OpenSSL CA vervangen"
- [decisions](../docs/decisions.nl.md): "Eigen homelab CA boven self-signed certificaten" (de voorganger)
- [YubiKey](../hardware/01-yubikey.nl.md): oorspronkelijk plan voor PIV signing, nu alleen als backup-authenticatie
- [Vaultwarden](04-vaultwarden.nl.md): opslag van key passphrases
