# Uptime Kuma

🇬🇧 [English](02-uptime-kuma.md) | 🇳🇱 Nederlands

Uptime Kuma bewaakt de beschikbaarheid van elke service en infrastructuurcomponent in het homelab. Het controleert elk target op een interval van 60 seconden en biedt een dashboard met uptimegeschiedenis.

## Waarom Uptime Kuma

Het homelab had een manier nodig om te weten wanneer iets uitvalt zonder elke service handmatig te controleren. Uptime Kuma vult deze rol met minimale overhead. Het gebruikt ongeveer 100 MB RAM, draait in een enkele Docker-container en ondersteunt HTTP-, TCP-, ping- en keyword-monitoring standaard.

Het alternatief was een Prometheus en Grafana stack, die diepere metrics biedt (CPU, geheugen, disk per service) maar 800+ MB RAM kost en exporters vereist op elke gemonitorde host. Voor een homelab met vijf services is dat niveau van detail buitenproportioneel. Uptime Kuma beantwoordt de enige vraag die ertoe doet: draait het of niet?

Als het homelab voorbij tien services groeit of prestatiemetrics nodig heeft, kan Prometheus naast Uptime Kuma worden toegevoegd in plaats van het te vervangen.

## Architectuur

Uptime Kuma draait als een enkele Docker-container in een LXC-container op het Apps VLAN. Data wordt opgeslagen in een Docker volume met SQLite.

```
LXC Container (CT 151)
┌──────────────────────────┐
│  Docker                  │
│  └─ Uptime Kuma (:3001)  │
│     └─ SQLite volume     │
└──────────────────────────┘
VLAN 40 (Apps)
```

## Container specs

| Instelling | Waarde |
|------------|--------|
| VMID | 151 |
| Type | LXC (unprivileged, nesting ingeschakeld) |
| Node | Node 1 |
| CPU | 1 core |
| RAM | 512 MB |
| Disk | 8 GB (LVM-thin) |
| VLAN | 40 (Apps) |
| IP | Statisch, toegewezen via containerconfiguratie |
| Boot | `onboot: 1` |

## Monitors

| Naam | Type | Target | Interval |
|------|------|--------|----------|
| n8n | HTTP | Publieke tunnel-URL | 60s |
| Proxmox Node 1 | HTTPS keyword | Management IP, poort 8006, keyword "Proxmox" | 60s |
| Proxmox Node 2 | HTTPS keyword | Management IP, poort 8006, keyword "Proxmox" | 60s |
| UniFi Gateway | Ping | Gateway IP | 60s |
| Uptime Kuma | HTTP | Localhost, poort 3001 | 60s |

De Proxmox monitors gebruiken keyword matching op de HTTPS-respons omdat een eenvoudige TCP-poortcheck zou slagen zelfs als de web UI een foutpagina teruggaf. Het keyword "Proxmox" bevestigt dat de loginpagina daadwerkelijk rendert.

TLS-verificatie is uitgeschakeld voor de Proxmox monitors omdat de nodes self-signed certificaten gebruiken.

## Netwerkvereisten

Uptime Kuma staat op het Apps VLAN en moet targets op andere VLANs bereiken. Twee firewallregels maken dit mogelijk:

1. **Netwerkfirewall:** Apps zone naar Servers zone, TCP 8006 (monitoring policy)
2. **Proxmox firewall:** Apps VLAN als bron, TCP 8006 en ICMP toegestaan

Zonder deze regels lopen de monitoring probes vast op een timeout omdat zowel de zone-based firewall als de host-level firewall Apps-naar-Servers verkeer standaard blokkeren.

## Toegang

Het dashboard is beschikbaar op `http://<container-ip>:3001` vanuit het Management VLAN. Er is geen publieke URL. Monitoringdata blijft intern.

## Backup

De container is opgenomen in de wekelijkse cluster backupjob. De SQLite database en alle monitorconfiguratie worden vastgelegd in de container-bestandssysteem snapshot.
