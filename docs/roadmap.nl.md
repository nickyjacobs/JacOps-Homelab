# Roadmap

🇬🇧 [English](roadmap.md) | 🇳🇱 Nederlands

Levend masterdocument voor het homelab-plan. Dit beschrijft waar we nu staan, wat de volgende stappen zijn, en welke expliciete keuzes er al gemaakt zijn. Wijzigingen aan dit plan worden gedocumenteerd in [decisions.nl.md](decisions.nl.md) en terugverwijzingen uit dit bestand worden bijgewerkt.

De roadmap is in vier fases ingedeeld. Fases kunnen parallel lopen wanneer ze elkaar niet blokkeren, maar de volgorde binnen een fase is bindend tenzij expliciet gewijzigd.

## Principes

Deze afspraken sturen elke deploy:

- **Alles intern via WireGuard.** Geen nieuwe publieke Cloudflare tunnels voor foundation services. n8n en Uptime Kuma houden hun bestaande tunnels omdat die al bestonden en een concrete externe use case hebben.
- **Nul secrets in de publieke repo.** Tokens, wachtwoorden, fingerprints en interne IPs worden vervangen door placeholders voordat een commit naar main gaat.
- **Container images pinnen op tag plus SHA256 digest.** Geen `latest` tags. Upgrades zijn bewuste acties.
- **Security-first defaults.** Elk service krijgt een dedicated service-account met scoped ACL's, 2FA waar mogelijk, audit logs aan. Root-accounts worden nooit gebruikt voor dagelijkse operaties.
- **Hardware 2FA via YubiKey 5C NFC.** Vanaf beschikbaarheid wordt de YubiKey de primaire tweede factor voor Vaultwarden, Bitwarden cloud, Proxmox VE en Forgejo. TOTP via Microsoft Authenticator blijft als backup en herstelpad.
- **Circular dependencies breken.** Elke service die zichzelf zou beschermen krijgt een alternatief herstelpad. PBS is daar het eerste voorbeeld van.
- **Discipline op credentials.** Zodra Vaultwarden draait, gaat elke nieuwe credential uit elke deploy direct daarheen. Geen papier, geen tekstbestanden op hosts.
- **Blue team tooling in pauze tot na eJPT.** Geen parallel security-tooling leren tijdens de eJPT-sprint. Velociraptor en alles wat daarbij hoort gaat pas aan na 17 mei 2026.

## Fase 0: Hardening en docs afronden

Het Proxmox cluster was al eerder netjes ingericht op het vlak van netwerk en host-hardening. Deze fase sluit de resterende gaten en synchroniseert de documentatie met de werkelijke staat.

### Gedaan

- SSH hardening op beide nodes: `PermitRootLogin prohibit-password`, `PasswordAuthentication no`, `X11Forwarding no`, `MaxAuthTries 3`, `ClientAliveInterval 300`, `ClientAliveCountMax 2`. `sshd -t` als validatie en `systemctl reload ssh` om bestaande sessies niet te breken.
- `sudo` geinstalleerd op beide nodes. De admin-user `nicky` is toegevoegd aan de `sudo`-groep met een NOPASSWD-sudoers entry zodat dagelijkse operaties niet op een gemist wachtwoord blokkeren.
- n8n compose (CT 150) heeft nu expliciete tag plus SHA256 digest pinning voor alle drie de containers: `n8n 2.13.4`, `postgres:16.13-alpine`, `cloudflared:2026.3.0`. De `:latest`-tags die er eerst stonden zijn verdwenen.
- De eerste handmatige `vzdump` plus restore-test is uitgevoerd op CT 151 (de monitoring-stack). De backup is teruggezet naar een wegwerp-CT 199, de config is geverifieerd, en de test-CT is opgeruimd. Dit was nodig omdat de geplande wekelijkse job nooit eerder had gedraaid.
- Zeven kleine `apt`-updates op beide nodes (acme, access-control, widget-toolkit, i18n, nvidia-vgpu, yew-mobile). Geen reboot nodig.
- `vm.swappiness=10` toegevoegd aan `/etc/sysctl.d/99-hardening.conf`. `SystemMaxUse=500M` in `journald.conf` om journal groei te bounden.
- Proxmox Backup Server volledig gedeployed inclusief datastore, ACL's, backup-jobs en maintenance-schedules. Zie [03-backups.nl.md](../proxmox/03-backups.nl.md) voor alle details.

### Open

- Negen firewall-tests uit `netwerk-verbeterplan.md` (cross-VLAN allow en deny verifieren vanuit Windows-lab-VM, Mac in Management VLAN, en iPhone via 4G plus WireGuard).
- Extra proxmox-docs in deze repo voor storage details, networking (VLAN-aware bridge), VM-hygiene (guest-agent, protection flags, tags) en monitoring. Niet urgent omdat de `03-backups`-doc de belangrijkste gap heeft dichtgezet.

## Fase 1: Foundation deployments

Acht services vormen samen de foundation-laag waar alle toekomstige werk op steunt. De volgorde is bindend: elke deploy in deze lijst beschermt of ondersteunt de volgende.

### Gedaan

**1. Proxmox Backup Server (PBS)**

VM 180 `pbs-01` op Node 1. Twee vCPU, 4 GB RAM, 32 GB OS-disk op de NVMe thin pool, 500 GB datastore als qcow2 op de SATA-directory. Dedicated service-account `pve-sync@pbs` met API-token plus `DatastoreBackup`-ACL scoped tot `/datastore/main`. Twee backup-jobs die samen de circular dependency wegwerken: `weekly-backup` voor alle VMs en containers naar PBS (zondag 03:00, vier weken retentie, VM 180 uitgesloten) en `pbs-self-backup` voor alleen VM 180 naar de oude SATA-directory (maandag 04:00, twee weken retentie). Datastore-onderhoud draait in een zondag-venster kort na de backup: garbage collection 05:00, prune 05:30, verify 06:00. Volledige uitleg in [03-backups.nl.md](../proxmox/03-backups.nl.md).

**2. Vaultwarden**

CT 152 op Node 1, Debian 13 base, een core, 512 MB RAM, 5 GB rootfs op de NVMe thin pool. Docker compose met Vaultwarden 1.35.4 en Caddy 2.11.2-alpine, beide gepind op tag plus SHA256 digest. Caddy als reverse proxy op dezelfde LXC met een certificaat ondertekend door de homelab CA. Intern-only via `vault.jacops.local`, alleen bereikbaar via WireGuard of het lokale netwerk. Admin token als Argon2id-hash in de env vars, `SIGNUPS_ALLOWED=false`, `INVITATIONS_ALLOWED=false`, `DISABLE_ICON_DOWNLOAD=true` als mitigatie tegen SSRF, `PASSWORD_ITERATIONS=600000` voor extra KDF-kosten.

Tweefactor via YubiKey 5C NFC als passkey (primair) en 2FAS Auth als TOTP-backup. Master password als diceware passphrase van minimaal twintig karakters.

Backups van de datastore lopen via de wekelijkse PBS backup job. Twee extra paden staan gepland: dagelijks via `restic` naar PBS, en wekelijks als encrypted tar via `age` naar een externe Backblaze B2 bucket. Renovate of een handmatige update-cyclus monitort nieuwe Vaultwarden releases en houdt de container binnen een week na elke security-patch bij.

Volledige documentatie in [services/04-vaultwarden.nl.md](../services/04-vaultwarden.nl.md).

**3. Forgejo v11 LTS**

CT 160 op Node 1, Debian 13 base, twee cores, 1 GB RAM, 20 GB rootfs op de SATA-directory. Binary install (Forgejo 11.0.12, geen Docker), SQLite database, systemd service met sandbox directives (NoNewPrivileges, ProtectSystem=strict, PrivateTmp, PrivateDevices). Caddy 2.11.2 als reverse proxy op dezelfde LXC met security headers (HSTS, X-Frame-Options, nosniff). Intern-only via `forgejo.jacops.local`, TLS via homelab CA. Ingebouwde SSH server op poort 2222 om een conflict met de runner te vermijden.

Security-hardening in app.ini: registratie uit, sign-in vereist voor alle pagina's, git hooks uitgeschakeld (RCE-mitigatie), SSRF-oppervlak beperkt (webhooks alleen private hosts, mirrors uit, packages uit, mailer uit). Admin-credentials direct in Vaultwarden opgeslagen. 2FA via YubiKey als WebAuthn passkey (primair) en 2FAS Auth als TOTP-backup.

Debian 13 in plaats van de geplande Debian 12 omdat alleen die template beschikbaar was op de node. Forgejo is een Go binary en is distro-onafhankelijk. Nesting ingeschakeld voor systemd 257 in unprivileged LXC, niet voor Docker.

Volledige documentatie in [services/05-forgejo.nl.md](../services/05-forgejo.nl.md).

**4. Forgejo Runner**

CT 161 op Node 2, Debian 13 base, twee cores, 2 GB RAM, 15 GB rootfs op de NVMe thin pool. LXC features `keyctl=1,nesting=1` voor Docker-in-LXC. Docker CE 29.4.0 en forgejo-runner v12.8.2 als systemd service met sandbox directives. Dedicated `forgejo-runner` service-gebruiker met Docker-groep lidmaatschap.

Geregistreerd als `homelab-runner` bij de Forgejo-instance op CT 160, met labels `ubuntu-latest`, `ubuntu-22.04` en `debian-latest`. Twee Forgejo-specifieke workflows in `.forgejo/workflows/` draaien als shadow-run naast de bestaande GitHub Actions: gitleaks (secret scanning) en lychee (link checking). De Forgejo-versies gebruiken CLI tools direct omdat de GitHub action wrappers niet compatibel zijn met de Forgejo runner (gitleaks vereist een betaalde licentie, lychee heeft PATH-problemen).

De homelab CA is vertrouwd in de container en wordt via volume mounts beschikbaar gemaakt in Docker job containers. `NODE_EXTRA_CA_CERTS` zorgt dat de checkout action de repository via HTTPS kan klonen. Actions is ingeschakeld in Forgejo's app.ini met `DEFAULT_ACTIONS_URL = https://github.com` zodat third-party actions direct resolven.

Debian 13 in plaats van de geplande Debian 12 voor consistentie met de Forgejo-container. Runner draait op Node 2 in plaats van Node 1 om de workload te spreiden.

Volledige documentatie in [services/06-forgejo-runner.nl.md](../services/06-forgejo-runner.nl.md).

**5. Miniflux**

CT 163 op Node 1, Debian 13 base, een core, 512 MB RAM, 5 GB rootfs op de NVMe thin pool. Docker compose met `miniflux/miniflux:2.2.6`, `postgres:16-alpine` en `caddy:2.11.2-alpine`, alle drie gepind op tag plus SHA256 digest. Caddy als reverse proxy met homelab CA cert. Intern-only via `miniflux.jacops.local`.

Debian 13 in plaats van de geplande Debian 12 omdat alleen die template beschikbaar was. RAM opgehoogd van 256 MB naar 512 MB en disk van 3 GB naar 5 GB omdat Miniflux, PostgreSQL, Caddy en de Docker daemon samen meer overhead vragen. Zie [decisions.nl.md](decisions.nl.md) voor de onderbouwing.

19 feeds verdeeld over drie categorieen. Threat Intel (7 feeds): SANS ISC, Microsoft Security Blog, Unit 42, CrowdStrike, Krebs on Security, The DFIR Report, BleepingComputer. Advisories (2 feeds): Debian Security Advisories (DSA) en PostgreSQL News. Releases (10 feeds): Vaultwarden, ntfy, Uptime Kuma, n8n, Miniflux, Caddy, Forgejo, Docker/Moby, Docker Compose en WireGuard. Feed-selectie op basis van signaal-ruisverhouding; Rapid7 en Cloudflare Blog zijn na evaluatie verwijderd wegens te veel marketing.

ntfy integratie geconfigureerd met dedicated publish-token en intern endpoint. API key aangemaakt voor toekomstige n8n-koppeling. Uptime Kuma monitor op het `/healthcheck` endpoint.

Volledige documentatie in [services/07-miniflux.nl.md](../services/07-miniflux.nl.md).

**6. step-ca**

CT 164 op Node 1, Debian 13 base, een core, 512 MB RAM, 5 GB rootfs op de NVMe thin pool. step-ca v0.30.2 als interne ACME server met two-tier PKI. Root CA offline op USB-drive, intermediate CA als software key op de LXC (JWE-versleuteld). EC P-256 voor de hele chain. ACME provisioner met 72 uur default cert lifetime en tls-alpn-01 challenge.

De oorspronkelijke beslissing specificeerde de intermediate key op YubiKey PIV slot 9c. Bij de implementatie bleek dit incompatibel met automatische ACME-certificaatuitgifte: de YubiKey zou 24/7 in de server moeten zitten en niet meer beschikbaar zijn voor WebAuthn. Software intermediate key is de standaard industrie-aanpak. Zie [decisions.nl.md](decisions.nl.md) voor de onderbouwing.

Volledige documentatie in [services/08-step-ca.nl.md](../services/08-step-ca.nl.md).

**7. Traefik**

CT 165 op Node 1, Debian 13 base, een core, 512 MB RAM, 5 GB rootfs op de NVMe thin pool. Traefik v3.6.13 als centraal reverse proxy voor alle foundation services. Vervangt de per-LXC Caddy-setups op Vaultwarden (CT 152), Forgejo (CT 160) en Miniflux (CT 163).

Automatische ACME-certificaten via step-ca met 72 uur lifetime. Globale security headers (HSTS, nosniff, frameDeny) op entrypoint-niveau. Dashboard beveiligd met basicAuth en IP allowlist. Backend verkeer is onversleuteld HTTP op hetzelfde VLAN, afgeschermd met iptables-regels per backend LXC (DOCKER-USER chain voor Docker services, INPUT chain voor native services).

DNS-records voor alle geproxyde services (miniflux, forgejo, vault) wijzen via UniFi DNS policies naar het Traefik IP.

Volledige documentatie in [services/09-traefik.nl.md](../services/09-traefik.nl.md).

**8. Beszel**

Beszel v0.18.7 als Docker container in CT 151 naast Uptime Kuma, ntfy en cloudflared. Image gepind op tag plus SHA256 digest. Hub op poort 8090, intern bereikbaar via `beszel.jacops.local` achter Traefik met automatisch step-ca certificaat.

Negen agents geinstalleerd: zeven foundation-LXCs (CT 151, 152, 160, 161, 163, 164, 165) via SSH-mode op poort 45876, twee PVE-nodes (srv-01, srv-02) via WebSocket-mode met per-system token direct naar de hub. De PVE-nodes vereisten een gerichte UniFi firewall-regel (Servers naar Apps, device-based, poort 8090 TCP) omdat de zone-firewall cross-VLAN verkeer standaard blokkeert.

Backend-firewall op CT 151: DOCKER-USER chain met ACCEPT voor de PVE-node IPs en Traefik, DROP voor de rest. Alerting via ntfy (Shoutrrr) met thresholds op CPU, RAM en disk (80%, 10 minuten) plus status alerts op alle negen systemen.

Volledige documentatie in [services/10-beszel.nl.md](../services/10-beszel.nl.md).

### Komend (volgorde bindend)

**9. Dockge**

In CT 150 naast de bestaande n8n-compose-stack, <100 MB RAM. Compose-UI voor alle Docker-stacks die op dezelfde daemon draaien. Intern-only via `dockge.jacops.local`. Dit vervangt het handmatige `docker compose`-werk voor Vaultwarden, Miniflux en eventuele latere compose-based services.

**10. ccusage**

Op MacBook via `bun install -g ccusage`. Nul infra op het cluster. Leest Claude Code's eigen JSONL session-logs in `~/.claude/projects/` en toont per-sessie, per-dag en per-model kosten. Statusline-hook in `~/.claude/settings.json` geeft live budget-zicht tijdens werk.

Dit vervangt de LiteLLM proxy uit eerdere plan-versies. Reden: LiteLLM's supply chain compromise van maart 2026, een cluster kritieke CVEs in Q1 2026 en cache_control regressies met Claude Code v2.0.76+. Zie [decisions.nl.md](decisions.nl.md) voor de volledige onderbouwing.

### Bijkomend buiten de cluster

**Bitwarden cloud gratis tier**

Persoonlijke credentials (bankzaken, social media, email, abonnementen) migreren uit Keeper naar Bitwarden cloud. Geen self-host omdat Bitwarden een dedicated security-team en Cure53-audits heeft die een solo-beheerde Vaultwarden-instance niet kan matchen voor de categorie credentials die bij een identiteitsramp horen.

YubiKey 5C NFC als primaire 2FA, aparte hardware-factor van Vaultwarden's YubiKey zodat een verloren apparaat niet beide vaults compromitteert (of één YubiKey met twee slots als dat praktischer is bij beschikbaarheid).

**Keeper**

Blijft in gebruik voor een beperkte werkcontext, buiten scope van deze repo. Geen persoonlijke of homelab-items meer in Keeper, zodat de lock-in beperkt blijft tot wat binnen de werkcontext toch al vastligt.

**TryHackMe Premium + HTB Starting Point**

TryHackMe Premium voor de duur van de eJPT-prep (veertien dollar per maand). Jr Penetration Tester path is het doel, niet random rooms. HTB Starting Point free tier als aanvullende boxes voor pattern recognition.

## Fase 2: eJPT practice stack

Parallel aan Fase 1, maar alleen deze drie componenten. De stack in eerdere plan-versies (Juice Shop, BBOT, ProjectDiscovery stack, Vulhub, GOAD) is geschrapt na de validatie-ronde tegen de eJPT v2 update van 26 maart 2026.

| Component | Plaats | Doel |
|-----------|--------|------|
| Docker host LXC | CT 170 op Node 1, Lab VLAN 30 | Geisoleerde container-runner voor practice targets |
| DVWA | Container in CT 170 | Web vulns: SQLi, XSS, command injection, file upload, CMS/WordPress-exploitation (nieuw in de eJPT v2 update) |
| Metasploitable 2 | Container of VM in CT 170 | MSFconsole workflow, host-enumeratie, klassieke exploit modules |
| Windows 10 Evaluation | VM op Node 2 | Local privesc met winPEAS, Microsoft 90-dagen gratis eval ISO |

Elke component in deze stack is direct aanwezig in de passing-blogs van 2024 tot en met 2026. Alles wat niet in die blogs opduikt is geschrapt.

Examendatum is 15 of 16 mei 2026. De sprint loopt vanaf 11 april, dus ongeveer 34 dagen. Studieschema-details staan buiten scope van dit roadmap-document en worden in persoonlijke planning bijgehouden.

## Fase 3: Na eJPT, vanaf 17 mei 2026

Blue team en red team tooling gaat vanaf 17 mei in gebruik, met Velociraptor voorop omdat die directe transferwaarde geeft naar SOC-werk in het algemeen, en naar Rapid7-gebaseerde omgevingen in het bijzonder.

| # | Service | Plaats | Reden |
|---|---------|--------|-------|
| 1 | Velociraptor | Server als LXC plus agents op doellab | Open source DFIR-agent, Rapid7-acquired, VQL leren, directe transferwaarde naar SOC-werk |
| 2 | Wazuh (lichte vorm, 4 GB RAM) | LXC of VM | Alternatieve SIEM naast Rapid7, SCA, FIM, vulnerability-scanning |
| 3 | MISP | LXC | Threat intel platform met community feeds |
| 4 | DFIR-IRIS | LXC | Case management, vervanger voor TheHive 5 sinds die commercieel werd |
| 5 | Sliver C2 | LXC in Lab VLAN 30 | Open source C2 voor OSEP-voorbereiding |
| 6 | GOAD-MINILAB via Ludus | Rotatie op Node 2 | AD pentest-basis met Ludus als orchestratie |
| 7 | SysReptor | LXC | Rapportage-engine voor JacOps, custom templates |

Parallel hieraan blijft lokaal op de MacBook: Atomic Red Team, Sigma-CLI, YARA-X en Chainsaw voor purple teaming-oefeningen. Deze tools vragen geen server-resources.

## Skiplijst: expliciet niet deployen

Deze services zijn afgevallen na kritische validatie. Ze staan hier zodat een latere sessie ze niet per ongeluk opnieuw voorstelt.

| Wat | Reden |
|-----|-------|
| LiteLLM | Supply chain compromise maart 2026 op PyPI v1.82.7 en v1.82.8, kritieke CVEs in Q1 2026 (OIDC auth bypass, privilege escalation, SQL injection), cache_control regressies met Claude Code v2.0.76 en verder, geen werkbare per-skill tracking door environment-variable limitaties. Vervangen door `ccusage`. |
| Apprise | ntfy v2.14 en v2.15 hebben inmiddels declarative users, ACL's, tokens en templates. Geen concrete use case meer die Apprise oplost. |
| Changedetection.io | Drie recente CVEs (SSRF, auth bypass, XSS). De meeste security-feeds hebben al RSS, Miniflux is lichter en veiliger. |
| Juice Shop | OSWE en bug bounty-terrein, niet eJPT volgens recente passing-blogs. |
| Metasploitable 3 | Frustrerend te deployen via Packer/Vagrant, geen winst boven Metasploitable 2 voor eJPT-scope. |
| BBOT | Bug bounty-recon framework, eJPT vraagt simpele nmap plus service enumeration. |
| ProjectDiscovery stack (nuclei, httpx, subfinder, dnsx) | Idem, bug bounty-tooling. |
| Vulhub rotatie | CVE-specifieke labs, eJPT test workflow niet CVE-knowledge. |
| GOAD, BadBlood, Vulnerable-AD voor eJPT | Meerdere 2026 passing-blogs bevestigen dat er geen AD op het eJPT-examen staat. |
| Homarr, Homepage | Nice-to-have dashboards, geen foundation. |
| Authentik, Authelia | SSO-broker pas waardevol bij vijf of meer web-UI's met veelvuldige login. Nu YAGNI. |
| Temporal, Apache Airflow, Prefect | Workflow-orchestratie overkill, n8n dekt het. |
| Helicone, Langfuse, Qdrant | LLM observability en vector-DB overkill zonder centrale LLM-proxy. |
| OpenCTI | Vraagt 16 GB RAM voor een stabiele single-node deploy. Te zwaar op deze hardware. |
| Security Onion 2 | Vraagt 200 GB disk en 8 tot 24 GB RAM. Te zwaar. |
| Nextcloud, Jellyfin, Pi-hole, AdGuard | Niet carriere-relevant, andere tools dekken de use cases. |
| Ollama op Proxmox zonder GPU | Te traag voor bruikbare LLM-inference, model-keuze blijft Claude via API. |
| CyberChef self-hosted | Offline tool, geen server-deploy nodig. |
| OpenVAS en GVM | Resource hog, Nuclei CLI dekt vuln-scanning voor homelab-schaal. |
| Publieke Cloudflare tunnels voor nieuwe foundation services | Alles intern via WireGuard. |

## Geschiedenis van deze roadmap

Het plan is in deze sessie drie keer aangepast:

1. Na de eerste research-ronde met drie parallelle agents stond er een uitgebreide maar ongefilterde foundation layer plus een brede eJPT stack.
2. Na een kritische validatie-ronde met drie nieuwe agents op foundation services, eJPT stack en LiteLLM specifiek zijn LiteLLM, Apprise en Changedetection.io geschrapt en is de eJPT stack flink ingekort.
3. Tijdens de deploy-sessie van 2026-04-11 is PBS volledig geinstalleerd en zijn Vaultwarden en Forgejo van volgorde gewisseld, zodat credentials direct in een vault landen in plaats van tijdelijk op hosts.
4. Tijdens de deploy-sessie van 2026-04-13 is Forgejo v11.0.12 LTS gedeployed op CT 160 met security-hardening (systemd sandbox, SSRF-beperking, git hooks uit). Debian 13 in plaats van Debian 12 wegens template-beschikbaarheid.
5. Tijdens de avondsessie van 2026-04-13 is de Forgejo Runner gedeployed op CT 161 (Node 2). Docker CE en forgejo-runner v12.8.2 met twee shadow-run workflows (gitleaks, lychee). Actions ingeschakeld in Forgejo. Debian 13 voor consistentie.
6. Tijdens de sessie van 2026-04-14 is Miniflux v2.2.6 gedeployed op CT 163 (Node 1). Docker Compose met PostgreSQL 16 en Caddy. 19 feeds in drie categorieen. ntfy integratie en Uptime Kuma monitor. RAM en disk opgehoogd van roadmap-spec. Architectuurbeslissingen genomen: Traefik als standaard reverse proxy (vervangt Caddy), step-ca als interne ACME server (vervangt handmatige OpenSSL CA).
7. Tijdens de sessie van 2026-04-15 zijn step-ca v0.30.2 (CT 164) en Traefik v3.6.13 (CT 165) gedeployed. Two-tier PKI met offline root key op USB en software intermediate key (YubiKey PIV afgevallen wegens incompatibiliteit met automatische ACME). Caddy verwijderd van CT 152, 160 en 163. Backend firewalling met iptables per LXC. Drie services gemigreerd naar centraal Traefik met automatische step-ca certificaten (72 uur lifetime).
8. Tijdens de sessie van 2026-04-16 is Beszel v0.18.7 gedeployed in CT 151. Negen agents: zeven LXCs via SSH-mode, twee PVE-nodes via WebSocket-mode met gerichte cross-VLAN firewall-regel. Universal token afgewezen ten gunste van handmatige per-system registratie. ntfy alerting en Uptime Kuma monitor geconfigureerd.
