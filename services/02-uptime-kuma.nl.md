# Uptime Kuma

🇬🇧 [English](02-uptime-kuma.md) | 🇳🇱 Nederlands

Uptime Kuma is het hart van de monitoring stack in het homelab. Het controleert elke service en infrastructuurcomponent op een interval van 60 seconden, verstuurt alerts via ntfy, en laat via een publieke status page zien of alles draait.

## Waarom Uptime Kuma

Het homelab had een manier nodig om te weten wanneer iets uitvalt zonder elke service met de hand na te lopen. Uptime Kuma vult die rol in met lage overhead. Het gebruikt zo'n 100 MB RAM, ondersteunt HTTP-, TCP-, ping-, DNS- en keyword-monitoring uit de doos, en heeft een overzichtelijk dashboard.

Het alternatief was een Prometheus en Grafana stack. Dat geeft meer diepgang (CPU, geheugen, disk per service) maar kost 800+ MB RAM en vraagt exporters op elke host die je meet. Voor een homelab met tien monitors is dat niveau detail meer dan nodig. Uptime Kuma beantwoordt de eerste vraag die telt: draait het of draait het niet?

Groeit het homelab voorbij de twintig services of komen er performance-metrics bij, dan kan Prometheus naast Uptime Kuma draaien in plaats van het te vervangen. Uptime Kuma heeft een eigen `/metrics` endpoint in Prometheus-formaat, dus een scrape job oppakken is een kleine stap.

## Architectuur

Uptime Kuma draait niet meer als losse container. Het is de hoofdservice in een monitoring stack met drie containers:

```
Internet ─── CDN Tunnel ─── Cloudflared ─────────┐
                                                 │
                LXC Container (CT 151)           │
                ┌────────────────────────────────┤
                │  Docker Compose                │
                │  ├─ Uptime Kuma (poort 3001)   │
                │  ├─ ntfy (poort 80 → 2586)     │
                │  └─ Cloudflared ───────────────┘
                └────────────────────────────────
                VLAN 40 (Apps)
```

Alle drie de containers delen één Docker netwerk. Uptime Kuma bereikt ntfy via dat netwerk op containernaam (`http://ntfy:80`), sneller en betrouwbaarder dan via de publieke URL gaan. De cloudflared container routeert twee publieke hostnames naar de interne services:

- `uptime.example.com` → `http://uptime-kuma:3001`
- `ntfy.example.com` → `http://ntfy:80`

Eén tunnel met meerdere hostnames is simpeler dan één tunnel per service. Beide services delen hetzelfde failure domain (de LXC), dus splitsen in twee tunnels maakt de opstelling niet veiliger. De volledige redenering staat in [docs/decisions.nl.md](../docs/decisions.nl.md).

De ntfy service staat apart beschreven in [03-ntfy.nl.md](03-ntfy.nl.md).

## Docker Compose

De volledige compose file van de monitoring stack:

```yaml
services:
  uptime-kuma:
    image: louislam/uptime-kuma:2
    container_name: uptime-kuma
    restart: always
    ports:
      - "3001:3001"
    volumes:
      - uptime-kuma:/app/data

  ntfy:
    image: binwiederhier/ntfy:latest
    container_name: ntfy
    restart: always
    command: serve
    ports:
      - "2586:80"
    volumes:
      - ntfy-cache:/var/cache/ntfy
      - ntfy-etc:/etc/ntfy
    environment:
      - TZ=Europe/Amsterdam
      - NTFY_BASE_URL=https://ntfy.example.com
      - NTFY_AUTH_DEFAULT_ACCESS=deny-all
      - NTFY_BEHIND_PROXY=true

  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    restart: always
    command: tunnel --no-autoupdate run
    environment:
      - TUNNEL_TOKEN=${CF_TUNNEL_TOKEN}

volumes:
  uptime-kuma:
    external: true
  ntfy-cache:
  ntfy-etc:
```

Het Uptime Kuma volume staat op `external: true` omdat het data volume al bestond vanuit een eerdere losse container. Extern houden voorkomt dat de data opnieuw wordt aangemaakt als de stack opnieuw wordt opgebouwd.

De `CF_TUNNEL_TOKEN` komt uit het Cloudflare Zero Trust dashboard zodra je de tunnel aanmaakt. Bewaar die buiten de compose file (environment variable of `.env`) en commit de echte waarde nooit.

## Container specs

| Instelling | Waarde |
|------------|--------|
| VMID | 151 |
| Type | LXC (unprivileged, nesting aan) |
| Node | Node 1 |
| CPU | 1 core |
| RAM | 1024 MB |
| Disk | 8 GB (LVM-thin) |
| VLAN | 40 (Apps) |
| IP | Statisch, toegewezen via containerconfiguratie |
| Boot | `onboot: 1` |

De RAM ligt hoger dan de oorspronkelijke 512 MB omdat er nu drie containers in de LXC draaien. Bij idle gebruik van rond de 400-500 MB geeft 1 GB genoeg ruimte voor pieken.

## Monitors

Tien monitors verdeeld over drie labels:

| Naam | Type | Target | Label |
|------|------|--------|-------|
| n8n | HTTP | Publieke tunnel-URL | Apps |
| Uptime Kuma (lokaal) | HTTP | `http://<container-ip>:3001` | Apps |
| Uptime Kuma (publiek) | HTTP | `https://uptime.example.com` | Apps |
| ntfy (lokaal) | HTTP | `http://ntfy:80/v1/health` | Apps |
| ntfy (publiek) | HTTP | `https://ntfy.example.com/v1/health` | Apps |
| Proxmox Node 1 | HTTPS keyword | Management IP, poort 8006, keyword "Proxmox" | Infrastructure |
| Proxmox Node 2 | HTTPS keyword | Management IP, poort 8006, keyword "Proxmox" | Infrastructure |
| UniFi Gateway | Ping | Gateway IP | Network |
| UniFi Switch | Ping | Switch IP | Network |
| UniFi Access Point | Ping | AP IP | Network |
| DNS Resolution | DNS | Publiek domein via 9.9.9.9 | Network |

De publieke en lokale varianten voor Uptime Kuma en ntfy zijn een bewuste keuze. Lokale checks (via het interne Docker netwerk) bevestigen dat de service zelf draait. Publieke checks lopen door de volle tunnelpad en bevestigen dat Cloudflare-routing, het TLS-certificaat en de reverse proxy headers werken. Slaagt de lokale check terwijl de publieke faalt, dan zit het probleem tussen de CDN edge en de container, niet in de container zelf.

De Proxmox monitors doen keyword matching op de HTTPS-respons omdat een gewone TCP-poortcheck zou slagen zelfs als de web UI een foutpagina teruggaf. Het keyword "Proxmox" bevestigt dat de loginpagina ook echt rendert. TLS-verificatie staat uit voor deze monitors omdat de nodes self-signed certificaten gebruiken.

n8n heeft alleen een publieke monitor omdat de n8n container zijn poort niet aan de LXC host geeft. Die poort is alleen bereikbaar vanuit het eigen Docker netwerk van n8n. De publieke URL is het enige pad.

## Labels

Drie labels geven de monitors structuur en sturen de groepering op de status page:

| Label | Kleur | Gebruikt voor |
|-------|-------|---------------|
| Infrastructure | Rood | Hypervisors, storage, de fundamenten |
| Network | Blauw | Gateway, switch, access point, DNS |
| Apps | Groen | Services op applicatieniveau (n8n, ntfy, Uptime Kuma zelf) |

Labels werken ook als filter op het dashboard. Met tien monitors is dat al handig, met dertig monitors wordt het nodig.

## Meldingen

Alle alerts lopen naar self-hosted ntfy. De Uptime Kuma notificatie staat ingesteld met:

- **Type:** ntfy
- **Server URL:** `http://ntfy:80` (intern Docker netwerk, niet de publieke URL)
- **Topic:** `homelab-alerts`
- **Authenticatie:** gebruikersnaam en wachtwoord

Het interne Docker netwerk gebruiken voor de notificatie-endpoint spaart een omweg door de Cloudflare tunnel voor elke alert. Het is sneller, en blijft werken als de tunnel even weg is. Dat is precies het moment waarop je de alert wilt ontvangen.

Custom templates maken de push op iOS in één oogopslag leesbaar:

- **Titel:** `{{ name }} is {{ status }}`
- **Bericht:** `{{ hostnameOrURL }} - {{ msg }}`

Dat levert alerts op zoals `Proxmox Node 1 is DOWN` met als body `10.0.10.x:8006 - Connection timeout`. Alles wat je op het lockscreen nodig hebt, niks waarvoor je de telefoon moet ontgrendelen.

Zie [03-ntfy.nl.md](03-ntfy.nl.md) voor de ntfy setup, met de gebruiker en de token die Uptime Kuma gebruikt om te publiceren.

## Status pages

Eén publieke status page draait op `https://uptime.example.com/status/public`. Die toont alleen de services die publiek mogen zijn:

- n8n (via de publieke URL)
- ntfy (de publieke endpoint)
- Uptime Kuma zelf (de publieke endpoint)

De interne infrastructuur (Proxmox nodes, UniFi hardware, DNS, lokale container checks) staat bewust niet op de publieke pagina. Een status page die interne IP's of hardwaremerken laat zien, geeft iedereen die rondsnuffelt gratis inzicht. De publieke versie richt zich op de diensten waar een externe bezoeker iets aan heeft.

Er komt geen losse wachtwoord-beveiligde status page. Uptime Kuma 2.x heeft de status page password-functie uit v1.x weggehaald. Voor interne weergave toont het admin panel op `https://uptime.example.com` alles, beschermd met login en 2FA.

## Beveiliging

Het admin panel is via de publieke tunnel bereikbaar, maar in lagen beschermd:

- **2FA (TOTP)** staat aan op het admin account
- **Sterk wachtwoord** voor de enige gebruiker
- **API key** heeft alleen toegang tot het `/metrics` endpoint en verloopt na drie maanden
- **Trust Proxy** staat op `Ja` omdat Uptime Kuma achter de Cloudflare tunnel zit en de forwarded headers nodig heeft voor correcte client IP logging
- **Base URL** wijst naar de publieke hostname zodat webhooks en redirects de tunnel-URL gebruiken in plaats van het lokale IP

De ingebouwde cloudflared tunnel van Uptime Kuma blijft bewust uit. Een losse cloudflared container naast Uptime Kuma is schoner: één tunnel-configuratie routeert zowel Uptime Kuma als ntfy, en de tunnel-lifecycle loopt via Docker in plaats van via het Uptime Kuma proces zelf.

## Netwerkvereisten

Uptime Kuma staat op het Apps VLAN en moet targets op meerdere andere zones bereiken. Drie firewallregels maken dat mogelijk:

1. **Apps naar Servers, TCP 8006** op de netwerkfirewall, voor de Proxmox web UI keyword checks
2. **Apps naar Mgmt, ICMP echo request** op de netwerkfirewall, voor de ping probes naar de switch en de access point
3. **Apps VLAN als bron toegestaan** in de Proxmox host firewall op TCP 8006 en ICMP, zodat de host-level firewall de probes niet dropt voordat ze de web UI bereiken

Zonder een van deze regels lopen de probes stil vast. De zone-based firewall dropt standaard wat niet expliciet is toegestaan, en de host-level firewall voegt een tweede laag toe die het ermee eens moet zijn.

## Toegang

Het dashboard staat op `https://uptime.example.com`, beveiligd met gebruikersnaam, wachtwoord en TOTP. Lokale toegang via `http://<container-ip>:3001` werkt nog vanuit het Management VLAN voor noodgevallen waarin DNS of de tunnel kapot is.

De publieke status page op `https://uptime.example.com/status/public` heeft geen login nodig.

## Backup

De container zit in de wekelijkse cluster backup job (zondag 03:00, zstd, vier weken retentie). Dat neemt het volledige container-bestandssysteem mee, met de drie Docker volumes (`uptime-kuma`, `ntfy-cache`, `ntfy-etc`) en dus alle monitor-configuratie, de ntfy user database en de config files.

Als extra veiligheid kun je de Uptime Kuma monitor configuratie als JSON exporteren vanuit het admin panel (Settings → Backup → Export). Houd een kopie buiten het homelab voor het scenario waarin beide nodes tegelijk hun disks verliezen.
