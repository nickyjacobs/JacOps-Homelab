# ntfy

🇬🇧 [English](03-ntfy.md) | 🇳🇱 Nederlands

ntfy is de self-hosted push notification service van het homelab. Uptime Kuma publiceert alerts naar ntfy, en de iOS app en webclients luisteren mee om ze te ontvangen. Het draait als container in dezelfde monitoring stack als Uptime Kuma.

## Waarom self-hosted

De voor de hand liggende keuze voor alerts is een derde partij: Telegram, Discord of e-mail via een transactionele provider. Die werken allemaal en zijn in vijf minuten klaar. Het nadeel: elke alert bevat de hostname, het IP of de URL van de service die down is gegaan. Voor een homelab dat bouwt aan security-first defaults voelt het verkeerd om die stroom door andermans infrastructuur te sturen.

ntfy is open source, licht (rond de 30-50 MB RAM) en simpel te draaien. De enige privacy-wissel voor iOS pushmeldingen is klein: de self-hosted server stuurt een poll-request naar de publieke `ntfy.sh` instantie, die vervolgens een APNs push via Apple naar de iPhone stuurt. Die upstream-request bevat alleen een SHA256 hash van de topic-naam plus het bericht-ID, niet de inhoud. De telefoon wordt wakker, authenticeert tegen de self-hosted server, en haalt het echte bericht direct daar op. De alert-inhoud verlaat het homelab dus niet.

Telegram en Discord kunnen later nog als back-up kanaal bij, als dat nodig blijkt. Voor nu is één betrouwbaar pad met goede privacy beter dan twee paden met lekkende metadata.

## Architectuur

ntfy is één container in de monitoring stack die wordt beschreven in [02-uptime-kuma.nl.md](02-uptime-kuma.nl.md). Het deelt de LXC en het Docker netwerk met Uptime Kuma en een cloudflared tunnel.

```
                    APNs push (alleen topic hash)
Telefoon ◄──────────────── ntfy.sh ◄──────┐
  │                                       │
  │ HTTPS (vol bericht ophalen, met auth) │
  ▼                                       │
  Cloudflared tunnel                      │ upstream poll request
  │                                       │
  ▼                                       │
  LXC Container (CT 151)                  │
  ┌────────────────────────────────┐      │
  │  Docker netwerk                │      │
  │  ├─ Uptime Kuma ──publiceer──► │      │
  │  └─ ntfy (poort 80) ─upstream──┴──────┘
  └────────────────────────────────┘
  VLAN 40 (Apps)
```

Twee dingen gebeuren parallel als een alert afgaat:

1. Uptime Kuma doet een POST naar `http://ntfy:80/homelab-alerts` via het interne Docker netwerk, met een bearer token. ntfy bewaart het in zijn cache en pusht het naar elke open webclient die op het topic zit.
2. ntfy stuurt daarnaast een poll-request naar `https://ntfy.sh/<hash>` waarbij `<hash>` gelijk is aan `SHA256(base-url + topic)`. Dat triggert `ntfy.sh` om een APNs push naar de iOS app te sturen. Die push is alleen een wake-up signaal, meer niet.

Als de iOS app de APNs push ontvangt, authenticeert hij tegen de self-hosted ntfy en haalt hij het echte bericht op. Die extra stap houdt de inhoud privé.

## Container specs

ntfy heeft geen eigen LXC. Het draait als Docker container in de Uptime Kuma monitoring LXC (CT 151). Zie [02-uptime-kuma.nl.md](02-uptime-kuma.nl.md) voor de container specs en de volledige docker-compose file.

Het ntfy service blok uit de compose:

```yaml
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
```

Poort 80 in de container is gemapt naar 2586 op de LXC host. Het externe poortnummer is willekeurig gekozen, zodat het niet botst met andere services op het Apps VLAN.

## Configuratie

De server-config staat in `/etc/ntfy/server.yml` in de container, persistent via het `ntfy-etc` volume:

```yaml
base-url: https://ntfy.example.com
listen-http: :80
auth-file: /var/cache/ntfy/user.db
auth-default-access: deny-all
behind-proxy: true
upstream-base-url: https://ntfy.sh
cache-file: /var/cache/ntfy/cache.db
cache-duration: 720h
```

Twee instellingen vragen aandacht:

**`auth-default-access: deny-all`** zet ntfy om van de default "iedereen mag lezen en schrijven op elk topic" naar "niemand mag iets tenzij je het expliciet toestaat". In combinatie met expliciete user-permissies kan niemand het alert topic lezen of schrijven zonder geldige credentials.

**`upstream-base-url: https://ntfy.sh`** is de instelling die iOS pushmeldingen werkend maakt. Zonder die regel komen berichten alsnog door op de iOS app, maar alleen als die op de achtergrond polled. iOS throttled dat agressief. Met het upstream-patroon krijgt de app een directe wake-up via APNs.

**Let op:** `NTFY_BASE_URL` in de compose environment moet exact gelijk zijn aan `base-url` in `server.yml`. Environment variables overschrijven de config file, dus een typo in één van de twee wint stil. En omdat de upstream hash wordt berekend uit de base URL, leidt een verschil tussen de server en de iOS app tot hashes die niet overeenkomen. Dan komen pushes nooit door. Meer hierover in [docs/lessons-learned.nl.md](../docs/lessons-learned.nl.md).

## Gebruikers en tokens

ntfy met `deny-all` heeft minstens één gebruiker nodig om iets te kunnen doen. Maak de admin user in de container aan:

```bash
docker exec -it ntfy ntfy user add --role=admin admin
```

Stel een sterk wachtwoord in. De admin-rol heeft lees- en schrijfrechten op elk topic.

Voor Uptime Kuma (of elke andere publisher) maak je een token aan in plaats van het wachtwoord te hergebruiken:

```bash
docker exec -it ntfy ntfy token add admin
```

De output is een token die begint met `tk_`. Gebruik die als bearer token in de publisher-config. Tokens kun je individueel intrekken zonder het wachtwoord te hoeven wijzigen.

Waarom een token en niet het admin-wachtwoord? Twee redenen:

1. **Blast radius:** raakt Uptime Kuma gecompromitteerd en lekt het token, dan trek je het token in. Als het wachtwoord lekt, moet je het op elke publisher en in het admin panel tegelijk veranderen.
2. **Audit:** tokens verschijnen als aparte identiteit in de logs. Je ziet welke publisher welk bericht heeft gestuurd.

Voor een solo homelab is dit aan de strenge kant, maar het is de juiste gewoonte om aan te leren.

## iOS pushmeldingen

De iOS app installeren is drie stappen:

1. Installeer ntfy uit de App Store.
2. Ga naar Settings, zet de default server op `https://ntfy.example.com` en voeg een gebruiker toe met de admin credentials.
3. Abonneer je op het topic `homelab-alerts`.

Test daarna vanaf de LXC of het hele pad werkt:

```bash
curl -H "Authorization: Bearer <NTFY_PUBLISH_TOKEN>" \
     -H "Title: Test" \
     -H "Priority: high" \
     -d "Komt dit binnen op het lockscreen?" \
     http://localhost:2586/homelab-alerts
```

Als het bericht in de app verschijnt zodra je hem opent, maar er geen banner of lockscreen-melding komt, dan zit er iets mis in de APNs pipeline. Check de troubleshooting sectie hieronder.

## Toegang

ntfy is bereikbaar via drie URLs, elk voor een ander doel:

| URL | Doel | Wie gebruikt het |
|-----|------|------------------|
| `http://ntfy:80` | Interne publish vanuit Uptime Kuma | Uptime Kuma via Docker netwerk |
| `http://<container-ip>:2586` | Lokaal beheer vanaf de LXC host | SSH troubleshooting |
| `https://ntfy.example.com` | Publieke web UI en iOS app endpoint | De telefoon, de browser |

De publieke URL is de normale route voor dagelijks gebruik. Het interne Docker-adres is wat Uptime Kuma gebruikt, zodat alerts blijven werken als de tunnel eventjes uitvalt. De LXC host-poort is het laatste redmiddel als er iets op netwerklaag kapot is.

## Beveiliging

Publiek bereikbaar is niet hetzelfde als open. Het `/v1/health` endpoint, de homepage en `/v1/config` geven data terug zonder login. Alles daarachter vereist authenticatie dankzij `auth-default-access: deny-all`:

| Endpoint | Auth vereist | Geeft terug |
|----------|--------------|-------------|
| `GET /` | Nee | HTML shell van de web UI |
| `GET /v1/health` | Nee | `{"healthy":true}` |
| `GET /v1/config` | Nee | Server config, zonder secrets |
| `GET /homelab-alerts/json?poll=1` | Ja | Geeft 403 zonder auth |
| `POST /homelab-alerts` | Ja | Geeft 403 zonder auth |
| `GET /homelab-alerts/auth` | Ja | Geeft 403 zonder auth |

De vorm is gelijk aan hoe `github.com` of `ntfy.sh` zelf werkt: de buitenkant is zichtbaar zodat gebruikers kunnen inloggen, maar de echte data zit achter auth. Een toevallige bezoeker ziet dat er ntfy draait en leert verder niets bruikbaars.

Drie extra hardeningsstappen bovenop de defaults:

- **Regelmatig updaten.** ntfy beweegt snel. `docker compose pull && docker compose up -d` één keer per maand houdt de container op een recente release.
- **Cloudflare rate limiting.** Het gratis Cloudflare plan throttled al misbruik-patronen. Een strengere rate-limit regel op het login endpoint is één klik extra als er brute force pogingen in de logs opduiken.
- **Monitor het topic.** Uptime Kuma kijkt zelf naar `https://ntfy.example.com/v1/health`. Valt de publieke endpoint uit, dan gaat de alert via... ntfy, wat een grappige circulaire afhankelijkheid oplevert. Voor echte breukmeldingen valt Uptime Kuma terug op de ingebouwde web UI notificatie.

## Troubleshooting iOS push

Als pushmeldingen stilvallen, loop dan deze checks af, op volgorde van waarschijnlijkheid:

**1. Topic-naam match.**
De topic-naam in Uptime Kuma en de topic-subscribe in de iOS app moeten identiek zijn. Een typo (`home-alerts` in plaats van `homelab-alerts`) geeft nergens een fout, alleen stilte.

**2. `base-url` match tussen config en env.**
`NTFY_BASE_URL` in de docker-compose file en `base-url` in `server.yml` moeten identieke strings zijn. Environment variables overschrijven de config file. Het upstream-patroon berekent een SHA256 hash uit de base URL. Een verschil tussen server en iOS app (zelfs een ander subdomein) geeft andere hashes, en dan komen pushes niet aan.

**3. Uitgaand verkeer naar `ntfy.sh`.**
Verifieer dat de container de upstream kan bereiken:

```bash
docker exec ntfy wget -qO- https://ntfy.sh/v1/health
```

Moet `{"healthy":true}` teruggeven. Zo niet, dan zit er ergens een blok in uitgaand netwerkverkeer.

**4. Debug logs voor het poll-request.**
Voeg tijdelijk `log-level: DEBUG` toe aan `server.yml` en herstart de container. Stuur een testbericht en grep in de logs:

```bash
docker logs ntfy 2>&1 | grep "Publishing poll request"
```

Verschijnt die regel, dan werkt de server-kant. Zo niet, dan klopt de upstream-config niet.

**5. iOS opnieuw registreren.**
Na een wijziging in `base-url` moet de iOS app zich opnieuw registreren met de nieuwe hash. Verwijder het abonnement, force-quit de app, start hem opnieuw en abonneer je opnieuw. In hardnekkige gevallen: verwijder de app volledig en installeer hem opnieuw.

**6. iOS notificatie-instellingen.**
Check dat Scheduled Summary uit staat voor ntfy (Settings → Notifications → ntfy) en dat Immediate Delivery aanstaat. Scheduled Summary verzamelt notificaties en levert ze op vaste tijden af, wat precies het tegenovergestelde is van wat je voor alerts wilt.

**7. Controle-test met een publiek topic.**
Abonneer je op een nieuw publiek topic op `https://ntfy.sh` (geen auth, geen upstream) en stuur een test. Komt die push wel binnen, dan is de iOS kant gezond en zit het probleem in de self-hosted config. Faalt die ook, dan ligt het aan het apparaat, niet aan de server.

## Backup

Het `ntfy-cache` volume bevat de SQLite user database, alle tokens en de gecachede berichten. Het `ntfy-etc` volume bevat de server config. Beide zitten in de wekelijkse LXC backup job.

`ntfy-cache` kwijtraken betekent dat je de admin user opnieuw aanmaakt en tokens opnieuw uitdeelt aan elke publisher. `ntfy-etc` kwijtraken betekent `server.yml` opnieuw schrijven. Geen van beide is een ramp, maar de backup is goedkoop en de restore is simpel, dus er is geen reden om het over te slaan.
