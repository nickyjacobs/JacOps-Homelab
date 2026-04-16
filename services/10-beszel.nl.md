# Beszel

🇬🇧 [English](10-beszel.md) | 🇳🇱 Nederlands

Beszel is de host-metrics monitoring van het homelab. Agents op alle LXC-containers en beide Proxmox nodes rapporteren CPU, RAM, disk, netwerk en meer naar een centrale hub. Het draait als Docker container in CT 151 naast Uptime Kuma, ntfy en cloudflared, intern bereikbaar via `beszel.jacops.local`.

## Waarom Beszel naast Uptime Kuma

Uptime Kuma beantwoordt de vraag "draait het of draait het niet?" met reachability checks op HTTP, TCP en ping. Dat is voldoende om te weten wanneer een service uitvalt, maar het zegt niks over waarom. Een container die 98% RAM gebruikt, een disk die volloopt of een CPU die continu op de limiet zit: dat zijn problemen die Uptime Kuma niet signaleert tot de service echt omvalt.

Beszel vult die blinde vlek in. De hub plus negen agents samen gebruiken minder dan 50 MB RAM. Dat is een fractie van wat een Prometheus plus Grafana stack zou kosten (800+ MB voor de stack alleen, plus exporters op elke host). Voor een homelab met twee nodes en negen containers is Beszel de juiste schaal.

## Architectuur

```
Browser ─── HTTPS ──► Traefik (CT 165)  ──► Beszel hub (CT 151)
                      :443                   :8090
                      step-ca ACME certs     Alleen via Traefik
                      Security headers       + PVE nodes

                          Beszel hub (CT 151)
                               │
              ┌────────────────┴────────────────┐
              │                                 │
         SSH (poort 45876)                 WebSocket (:8090)
              │                                 │
    ┌─────────┴──────────┐            ┌─────────┴─────────┐
    │ VLAN 40 (Apps)     │            │ VLAN 10 (Servers)  │
    │ CT 151,152,160     │            │ PVE Node 1         │
    │ CT 161,163,164,165 │            │ PVE Node 2         │
    └────────────────────┘            └────────────────────┘
```

Twee verbindingsmodi:

- **SSH modus** voor de zeven LXC-containers op VLAN 40 (CT 151, 152, 160, 161, 163, 164, 165). De hub initieert de verbinding naar de agent op poort 45876. Geen extra firewallregels nodig omdat alle containers op hetzelfde VLAN zitten
- **WebSocket modus** voor de twee Proxmox nodes op VLAN 10 (ander subnet dan de hub). De agents initieren de verbinding naar de hub op poort 8090. Dit voorkomt dat de hub cross-VLAN verbindingen moet opzetten naar het Servers VLAN

Geen publieke tunnel, geen Cloudflare. De service is alleen bereikbaar via het lokale netwerk of WireGuard.

## Container specs

De hub draait in CT 151, dezelfde LXC als de monitoring stack (Uptime Kuma, ntfy, cloudflared).

| Instelling | Waarde |
|------------|--------|
| VMID | 151 |
| Type | LXC (unprivileged) |
| Node | Node 1 |
| OS | Debian 13 (Trixie) |
| CPU | 1 core |
| RAM | 512 MB |
| Swap | 256 MB |
| Disk | 8 GB op LVM-thin (`local-lvm`) |
| VLAN | 40 (Apps) |
| IP | Statisch, toegewezen via containerconfiguratie |
| Boot | `onboot: 1` |
| Features | `nesting=1` (vereist voor Docker) |
| Tags | `docker`, `homelab`, `monitoring` |

## Docker Compose

Beszel is toegevoegd aan de bestaande compose stack in `/opt/monitoring/` op CT 151. Alleen het Beszel-fragment:

```yaml
services:
  beszel:
    image: henrygd/beszel:0.18.7@sha256:<digest>
    container_name: beszel
    restart: always
    ports:
      - "8090:8090"
    volumes:
      - beszel-data:/beszel_data

volumes:
  beszel-data:
```

Het image is gepind op tag plus SHA256 digest. De hub luistert op poort 8090 voor zowel de web UI als de WebSocket-verbindingen van de PVE node agents.

## Agent installatie

Alle negen agents draaien Beszel v0.18.7 als Go binary, geinstalleerd via het officiele installatiescript:

```bash
curl -sL https://get.beszel.dev | bash
```

Elke agent draait als systemd service onder een dedicated `beszel` user:

| Instelling | Waarde |
|------------|--------|
| Binary | `/usr/local/bin/beszel-agent` |
| User | `beszel` (dedicated service-user) |
| Groepen | `disk` (voor disk-metrics), `docker` (op Docker-based CTs) |
| Poort | 45876 |
| systemd unit | `beszel-agent.service` |

### systemd hardening

De agent service unit bevat sandbox directives:

| Directive | Effect |
|-----------|--------|
| `User=beszel` | Dedicated service-user, geen root |
| `NoNewPrivileges=true` | Voorkomt privilege escalation |
| `ProtectSystem=strict` | Filesystem read-only |
| `ProtectHome=true` | Geen toegang tot /home |
| `PrivateTmp=true` | Eigen /tmp namespace |

### Agents overzicht

| Host | VMID | VLAN | Modus | Groepen |
|------|------|------|-------|---------|
| Monitoring stack | CT 151 | 40 | SSH | `disk`, `docker` |
| Vaultwarden | CT 152 | 40 | SSH | `disk`, `docker` |
| Forgejo | CT 160 | 40 | SSH | `disk` |
| Forgejo Runner | CT 161 | 40 | SSH | `disk`, `docker` |
| Miniflux | CT 163 | 40 | SSH | `disk`, `docker` |
| step-ca | CT 164 | 40 | SSH | `disk` |
| Traefik | CT 165 | 40 | SSH | `disk` |
| PVE Node 1 | - | 10 | WebSocket | `disk` |
| PVE Node 2 | - | 10 | WebSocket | `disk` |

## Verbindingsmodi

### SSH modus (VLAN 40 containers)

De hub verbindt naar de agent via SSH op poort 45876. Bij het toevoegen van een systeem in de Beszel UI genereert de hub een SSH key pair. De publieke sleutel wordt toegevoegd aan de agent-configuratie. De hub initieert alle verbindingen, de agent luistert passief.

Dit werkt voor alle containers op hetzelfde VLAN als de hub. Geen extra firewallregels of zone-policies nodig.

### WebSocket modus (PVE nodes, VLAN 10)

De PVE nodes staan op het Servers VLAN (10), een ander subnet dan de hub op het Apps VLAN (40). In SSH modus zou de hub cross-VLAN verbindingen moeten initieren, wat een bredere firewallregel vereist.

WebSocket draait dit om: de agent initieert de verbinding naar de hub. Elke PVE node agent krijgt een uniek per-system token uit de Beszel UI en verbindt naar `http://<ct-ip>:8090`. De hub accepteert de verbinding op basis van het token.

De firewallregel is scoped tot het minimum: alleen de twee PVE nodes mogen poort 8090 op CT 151 bereiken vanuit VLAN 10.

## Traefik route

De Beszel web UI is bereikbaar via `beszel.jacops.local` achter Traefik. De dynamische configuratie op CT 165:

**svc-beszel.yml**

```yaml
http:
  routers:
    beszel:
      rule: "Host(`beszel.jacops.local`)"
      entryPoints:
        - websecure
      service: beszel
      tls:
        certResolver: step-ca
  services:
    beszel:
      loadBalancer:
        servers:
          - url: "http://<ct-ip>:8090"
        healthCheck:
          path: /api/health
          interval: 30s
          timeout: 5s
```

Het ACME-certificaat wordt automatisch aangevraagd bij step-ca met een geldigheid van 72 uur en vernieuwt via tls-alpn-01 zonder handmatige tussenkomst. Security headers (HSTS, nosniff, frameDeny) worden globaal door Traefik toegepast.

## Backend firewall

CT 151 heeft drie lagen van toegangsbeperking op poort 8090:

### iptables op CT 151

De DOCKER-USER chain beperkt wie poort 8090 kan bereiken:

```
iptables -I DOCKER-USER -p tcp --dport 8090 -s <node1-ip> -j ACCEPT
iptables -I DOCKER-USER -p tcp --dport 8090 -s <node2-ip> -j ACCEPT
iptables -I DOCKER-USER -p tcp --dport 8090 ! -s <traefik-ip> -j DROP
```

De volgorde is belangrijk: de twee ACCEPT-regels voor de PVE nodes staan boven de DROP-regel. Verkeer van de nodes wordt toegestaan voor de WebSocket-verbindingen, al het andere verkeer naar poort 8090 dat niet van Traefik komt wordt gedropt. `iptables-persistent` zorgt dat de regels een reboot overleven.

### UniFi zone firewall

Een device-based policy staat verkeer toe van de twee PVE nodes (Servers zone) naar CT 151 (Apps zone) op TCP poort 8090. Zonder deze regel dropt de zone-based firewall het cross-VLAN verkeer voordat het de LXC bereikt.

| Instelling | Waarde |
|------------|--------|
| Richting | Servers naar Apps |
| Type | Device-based |
| Bronnen | PVE Node 1, PVE Node 2 |
| Bestemming | CT 151 IP, TCP 8090 |

### Resultaat

Poort 8090 is alleen bereikbaar voor drie IP-adressen: de twee PVE nodes (WebSocket agents) en het Traefik IP (web UI proxy). Alle andere hosts worden op twee niveaus gedropt: de zone-firewall en de iptables-regels op de container.

## Alerting

Beszel stuurt alerts naar ntfy via de ingebouwde Shoutrrr-integratie. Het ntfy endpoint is het interne Docker netwerk, niet de externe URL:

| Instelling | Waarde |
|------------|--------|
| Provider | ntfy via Shoutrrr |
| Endpoint | `ntfy://:tk_<token>@ntfy:80/beszel-alerts?scheme=http` |
| Transport | Intern Docker netwerk (container-naar-container) |

Het token is een dedicated publish-token voor het `beszel-alerts` topic. De waarde staat in Vaultwarden als `homelab/beszel-ntfy-publish-token`.

### Alert-drempels

Vier alertregels gelden voor alle negen systemen:

| Metric | Drempel | Duur | Actie |
|--------|---------|------|-------|
| CPU | 80% | 10 minuten | ntfy alert |
| Memory | 80% | 10 minuten | ntfy alert |
| Disk | 80% | 10 minuten | ntfy alert |
| Status | Down | Direct | ntfy alert |

De duur van 10 minuten voorkomt alerts bij korte pieken (apt upgrades, Docker image pulls, feed polling). Alleen aanhoudende belasting triggert een melding.

## Metrics

Beszel verzamelt de volgende metrics per systeem:

| Categorie | Metrics |
|-----------|---------|
| CPU | Gebruik (%), load average |
| Geheugen | Gebruik (%), vrij, swap |
| Disk | Gebruik (%), I/O (lezen/schrijven) |
| Netwerk | Bandbreedte (in/uit) |
| Temperatuur | CPU-temperatuur (waar beschikbaar) |
| Services | Docker containers, systemd services |
| Uptime | Systeemuptime |

Op Docker-based containers (CT 151, 152, 161, 163) toont Beszel per-container resource-gebruik. Dit geeft zicht op welke container binnen een LXC de meeste resources verbruikt.

## Security

### Waarom geen universal token

Beszel biedt twee registratiemethoden voor agents: een universal token (gedeeld geheim dat elke agent automatisch registreert) en handmatige per-system registratie via de UI.

De universal token is afgewezen. Een enkel gedeeld geheim betekent dat iedereen met dat token een willekeurig systeem kan registreren als agent. Op een netwerk met meerdere VLANs en zone-based firewalling ondermijnt dat de segmentatie. Een gelekt token geeft een aanvaller een pad om data naar de hub te sturen zonder expliciete autorisatie.

Handmatige registratie per systeem vereist dat elk nieuw systeem expliciet wordt toegevoegd via de Beszel web UI. De hub genereert een uniek SSH key pair (SSH modus) of een uniek token (WebSocket modus) per systeem. De operationele last is minimaal: negen systemen toevoegen kostte minder dan vijf minuten.

### Credentials

| Secret | Vaultwarden pad |
|--------|-----------------|
| Beszel admin account | `homelab/beszel-admin` |
| ntfy publish-token | `homelab/beszel-ntfy-publish-token` |
| PVE Node 1 WebSocket token | `homelab/beszel-node1-ws-token` |
| PVE Node 2 WebSocket token | `homelab/beszel-node2-ws-token` |

## Monitoring

Uptime Kuma monitort de Beszel web UI met een HTTPS check:

| Instelling | Waarde |
|------------|--------|
| Type | HTTPS |
| URL | `https://beszel.jacops.local` |
| TLS-verificatie | Aan (step-ca root CA is trusted) |
| Interval | 60 seconden |
| Notificatie | ntfy homelab-alerts topic |

Bij uitval stuurt Uptime Kuma een alert naar ntfy. De monitoring loopt via een apart pad (Uptime Kuma naar ntfy) dan de Beszel alerting zelf (Beszel naar ntfy), zodat een probleem met Beszel niet zijn eigen alert onderdrukt.

## Toegang

| Pad | Doel |
|-----|------|
| `https://beszel.jacops.local` | Web UI (dagelijks gebruik) |
| `https://beszel.jacops.local/api/health` | Health check endpoint |

Beide zijn alleen bereikbaar via het lokale netwerk of WireGuard. Er is geen publieke URL.

## Backup

De container is opgenomen in de wekelijkse PBS backup job (zondag 03:00, vier weken retentie). Dit vangt het volledige container-bestandssysteem van CT 151 inclusief alle Docker volumes: Beszel data, Uptime Kuma data, ntfy cache en configuratie.

## Gerelateerd

- [Roadmap](../docs/roadmap.nl.md): Beszel is de achtste foundation service in Fase 1
- [Uptime Kuma](02-uptime-kuma.nl.md): reachability monitoring op dezelfde LXC, Beszel voegt host-metrics toe
- [ntfy](03-ntfy.nl.md): push-notificaties voor Beszel alerts via het interne Docker netwerk
- [Traefik](09-traefik.nl.md): reverse proxy en TLS-terminatie via step-ca
- [step-ca](08-step-ca.nl.md): automatische ACME-certificaten voor de Traefik route
