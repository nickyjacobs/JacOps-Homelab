# Forgejo Runner

🇬🇧 [English](06-forgejo-runner.md) | 🇳🇱 Nederlands

De Forgejo Runner voert CI/CD workflows uit voor repositories op de Forgejo-instance. Het draait als systemd service in een eigen LXC-container op Node 2, met Docker als execution backend voor workflow jobs.

## Waarom een eigen runner

De bestaande GitHub Actions workflows (link checking met lychee, secret scanning met gitleaks) draaien op GitHub-hosted runners. Een eigen runner op het cluster maakt het mogelijk om dezelfde checks lokaal uit te voeren zonder afhankelijkheid van GitHub's infrastructuur. De runner draait op Node 2 om de workload te spreiden ten opzichte van Forgejo zelf (Node 1).

Forgejo Actions is compatibel met het GitHub Actions workflow-formaat. De workflows in `.forgejo/workflows/` gebruiken dezelfde YAML-syntax maar vervangen GitHub-specifieke action wrappers door directe CLI tools. De `.github/workflows/` blijven ongewijzigd voor GitHub.

## Architectuur

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

De runner pollt de Forgejo API elke twee seconden voor nieuwe jobs. Bij een trigger (push, schedule, workflow_dispatch) start de runner een Docker container met het juiste base image, kloont de repository, en voert de workflow stappen uit. Logs worden teruggestuurd naar Forgejo en zijn zichtbaar in de web UI.

## Container specs

| Instelling | Waarde |
|------------|--------|
| VMID | 161 |
| Type | LXC (unprivileged) |
| Node | Node 2 |
| OS | Debian 13 (Trixie) |
| CPU | 2 cores |
| RAM | 2048 MB |
| Swap | 512 MB |
| Disk | 15 GB op NVMe thin pool (`local-lvm`) |
| VLAN | 40 (Apps) |
| IP | Statisch, toegewezen via containerconfiguratie |
| Boot | `onboot: 1` |
| Features | `keyctl=1,nesting=1` (vereist voor Docker-in-LXC) |
| Tags | `forgejo-runner`, `homelab` |

De rootfs staat op de NVMe thin pool. Docker image pulls en container I/O profiteren van de snellere opslag. `keyctl=1` en `nesting=1` zijn beide nodig om Docker correct te laten draaien in een unprivileged LXC-container.

## Software

| Component | Versie | Installatie |
|-----------|--------|-------------|
| Docker CE | 29.4.0 | Via het officiele Docker APT repository |
| forgejo-runner | 12.8.2 | Binary in `/usr/local/bin/forgejo-runner`, SHA256-geverifieerd |

## Configuratie

### Runner config

De runner config staat in `/var/lib/forgejo-runner/config.yml`. De registratie-informatie (token, UUID, instance URL) staat in `/var/lib/forgejo-runner/.runner`.

| Instelling | Waarde | Reden |
|------------|--------|-------|
| `capacity` | `1` | Een job tegelijk, voorkomt resource contention |
| `NODE_EXTRA_CA_CERTS` | `/etc/ssl/certs/jacops-homelab-step-root-ca.crt` | Node.js (checkout action) vertrouwt de step-ca root CA |
| `docker_host` | `automount` | Docker socket automatisch gemount in job containers |
| Container options | CA cert en CA bundle volume mounts | TLS-verificatie werkt in job containers |

### Labels

| Label | Docker image | Gebruik |
|-------|-------------|---------|
| `ubuntu-latest` | `node:20-bookworm` | Default voor de meeste workflows |
| `ubuntu-22.04` | `ubuntu:22.04` | Specifieke Ubuntu-versie |
| `debian-latest` | `debian:trixie-slim` | Lichtgewicht Debian |

### TLS en de step-ca root CA

Job containers draaien geisoleerd en vertrouwen de step-ca root CA niet standaard. Het CA-certificaat komt van de step-ca PKI (CT 164) en wordt via volume mounts beschikbaar gemaakt in job containers:

- `/usr/local/share/ca-certificates/jacops-homelab-step-root-ca.crt` wordt gemount als `/etc/ssl/certs/jacops-homelab-step-root-ca.crt` (individueel CA-certificaat)
- `/etc/ssl/certs/ca-certificates.crt` van de host wordt gemount in de container (volledige CA-bundle inclusief de step-ca root CA)

`NODE_EXTRA_CA_CERTS` vertelt Node.js om de step-ca root CA toe te voegen aan de vertrouwde lijst. Dit is nodig voor de `actions/checkout` stap die de repository kloont via HTTPS van Forgejo.

### Forgejo-side configuratie

Actions is ingeschakeld in Forgejo's `app.ini`:

```ini
[actions]
ENABLED = true
DEFAULT_ACTIONS_URL = https://github.com
```

`DEFAULT_ACTIONS_URL` wijst naar GitHub zodat third-party actions (checkout, lychee, gitleaks) direct resolven zonder volledige URL's in de workflow files.

## Security

### Service-gebruiker

De runner draait als een dedicated `forgejo-runner` gebruiker met lidmaatschap van de `docker` groep. Geen shell (`/usr/sbin/nologin`), home directory in `/var/lib/forgejo-runner`.

### systemd hardening

| Directive | Effect |
|-----------|--------|
| `NoNewPrivileges=true` | Voorkomt privilege escalation |
| `ProtectSystem=strict` | Filesystem read-only behalve toegestane paden |
| `ProtectHome=true` | Geen toegang tot /home |
| `PrivateTmp=true` | Eigen /tmp namespace |
| `ReadWritePaths` | Alleen `/var/lib/forgejo-runner` |

### Beperkte scope

De runner registratie is instance-wide, niet per-repository. De runner voert alleen jobs uit die matchen met zijn labels. Docker containers voor jobs zijn ephemeral en worden na afloop opgeruimd.

## Status: proof-of-concept

De runner is operationeel en getest, maar draait als proof-of-concept. De workflows in `.forgejo/workflows/` triggeren alleen op `workflow_dispatch` (handmatig), niet bij elke push. Reden: deze repo is publiek op GitHub en de GitHub Actions workflows dekken CI al volledig. Dezelfde checks automatisch op Forgejo draaien is dubbel werk.

De runner wordt productie-relevant zodra:
- Er private repositories in Forgejo komen (configs, scripts, compose files die niet op GitHub horen)
- Er workflows nodig zijn die het cluster raken (deploy scripts, backup verificatie)
- De GitHub-afhankelijkheid bewust afgebouwd wordt

## Workflows

Twee workflows staan klaar voor handmatige uitvoering:

| Workflow | Doel | Trigger |
|----------|------|---------|
| `gitleaks.yml` | Secret scanning via gitleaks CLI | workflow_dispatch |
| `lychee.yml` | Link checking via lychee CLI | workflow_dispatch |

Triggeren via de Forgejo web UI (Actions > workflow > "Run Workflow") of via de API.

De Forgejo-versies staan in `.forgejo/workflows/` en gebruiken CLI tools direct in plaats van GitHub-specifieke action wrappers. De `.github/workflows/` versies blijven ongewijzigd en draaien op GitHub.

**Verschil met GitHub-versies:**

- `gitleaks`: de GitHub action (v2) vereist een betaalde licentie buiten GitHub. De Forgejo-versie download de gitleaks binary direct
- `lychee`: de GitHub action heeft PATH-problemen in de act runner. De Forgejo-versie installeert lychee als binary

## Backup

CT 161 is opgenomen in de wekelijkse PBS backup job (zondag 03:00, vier weken retentie). De runner zelf is stateless op applicatieniveau: het registratiebestand en de config zijn het enige dat bewaard hoeft te worden. Bij verlies van de container is een herregistratie met een nieuw token sneller dan een restore.

## Gerelateerd

- [Forgejo](05-forgejo.nl.md): de Git forge waar deze runner bij hoort
- [Roadmap](../docs/roadmap.nl.md): Forgejo Runner is de vierde foundation service
- [Vaultwarden](04-vaultwarden.nl.md): API token opgeslagen als `homelab/forgejo-api-token-ci-setup`
