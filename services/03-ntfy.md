# ntfy

🇬🇧 English | 🇳🇱 [Nederlands](03-ntfy.nl.md)

ntfy is the self-hosted push notification service for the homelab. Uptime Kuma publishes alerts to it, and the iOS and web clients subscribe to receive them. It runs as a container inside the monitoring stack alongside Uptime Kuma.

## Why self-hosted

The obvious choice for alert delivery is a third-party messaging service: Telegram, Discord, or email through a transactional provider. They all work and they all take five minutes to set up. But each alert carries the hostname, IP or URL of the service that went down. For a homelab that is building toward security-first defaults, sending that data through someone else's servers feels like the wrong direction.

ntfy is open source, lightweight (around 30-50 MB of RAM) and straightforward to run. The only trade-off for iOS push notifications is a small privacy give-up: the self-hosted server forwards a poll request to the public `ntfy.sh` instance, which then sends an APNs push to Apple. The upstream request only contains a SHA256 hash of the topic name and the message ID, not the content. The phone wakes up, authenticates against the self-hosted server, and fetches the actual message body directly. The alert content never leaves the homelab.

Telegram and Discord can still be added as backup channels later. For now, one reliable path with good privacy beats two paths with leaky metadata.

## Architecture

ntfy is a single container in the monitoring stack documented in [02-uptime-kuma.md](02-uptime-kuma.md). It shares the LXC container and the Docker network with Uptime Kuma and a cloudflared tunnel.

```
                    APNs push (topic hash only)
Phone ◄───────────────────── ntfy.sh ◄──────┐
  │                                         │
  │ HTTPS (fetch full message, authenticated)│
  ▼                                         │
  Cloudflared tunnel                        │ upstream poll request
  │                                         │
  ▼                                         │
  LXC Container (CT 151)                    │
  ┌────────────────────────────────┐        │
  │  Docker network                │        │
  │  ├─ Uptime Kuma ──publish──►───┤        │
  │  └─ ntfy (port 80) ─upstream───┴────────┘
  └────────────────────────────────┘
  VLAN 40 (Apps)
```

Two things happen in parallel when an alert fires:

1. Uptime Kuma POSTs the alert to `http://ntfy:80/homelab-alerts` over the internal Docker network, using a bearer token. ntfy stores it in its cache and pushes it to any open web client subscriptions.
2. ntfy also sends a poll request to `https://ntfy.sh/<hash>` where `<hash>` is `SHA256(base-url + topic)`. That triggers `ntfy.sh` to send an APNs push to the iOS app. The push is a wake-up signal, nothing more.

When the iOS app receives the APNs push, it authenticates against the self-hosted ntfy and fetches the actual message body. That roundtrip is what keeps the message content private.

## Container specs

ntfy does not have its own LXC. It runs inside the Uptime Kuma monitoring LXC (CT 151) as a Docker container. See [02-uptime-kuma.md](02-uptime-kuma.md) for the full container specs and the complete docker-compose file.

The ntfy service block from the compose:

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

Port 80 inside the container is mapped to 2586 on the LXC host. The external port value is arbitrary, picked to avoid collisions with anything else in the Apps VLAN.

## Configuration

The server config lives in `/etc/ntfy/server.yml` inside the container, persisted through the `ntfy-etc` volume:

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

Two settings deserve attention:

**`auth-default-access: deny-all`** flips ntfy from the default "anyone can subscribe and publish to any topic" to "nothing is allowed unless explicitly granted." Combined with explicit user permissions, this means nobody can read or write the alert topic without credentials.

**`upstream-base-url: https://ntfy.sh`** is the setting that makes iOS push notifications work. Without it, the iOS app still receives messages eventually, but only when it polls in the background, which iOS throttles aggressively. The upstream pattern lets the app get an instant wake-up from APNs.

**Important:** `NTFY_BASE_URL` in the compose environment must match `base-url` in `server.yml` exactly. Environment variables override the config file, so a typo in one place silently wins. And because the upstream hash is computed from the base URL, a mismatch between the server and the iOS app means the hashes do not line up, and pushes never arrive. There is more on this in [docs/lessons-learned.md](../docs/lessons-learned.md).

## Users and tokens

ntfy with `deny-all` needs at least one user to do anything. Create the admin user inside the container:

```bash
docker exec -it ntfy ntfy user add --role=admin admin
```

Set a strong password. The admin role has full read/write access to every topic.

For Uptime Kuma (or any other publisher) generate a token instead of embedding the password:

```bash
docker exec -it ntfy ntfy token add admin
```

The output is a token starting with `tk_`. Use it as a bearer token in the publisher config. Tokens can be revoked individually without rotating the password.

Why a token instead of the admin password? Two reasons:

1. **Blast radius:** if Uptime Kuma is compromised and the bearer token leaks, you revoke the token. If the admin password leaked, you would have to change the password on every publisher and the web UI at the same time.
2. **Audit:** tokens show up as a separate identity in logs. You can see exactly which publisher sent which message.

For a solo homelab this is mild overkill, but it is the right habit to build.

## iOS push notifications

Setting up the iOS app is three steps:

1. Install ntfy from the App Store.
2. In Settings, set the default server to `https://ntfy.example.com` and add a user with the admin credentials.
3. Subscribe to the topic `homelab-alerts`.

After that, publish a test message from the LXC to verify the full path works:

```bash
curl -H "Authorization: Bearer <NTFY_PUBLISH_TOKEN>" \
     -H "Title: Test" \
     -H "Priority: high" \
     -d "Does this show up on the lock screen?" \
     http://localhost:2586/homelab-alerts
```

If the message appears in the app when you open it but no banner or lock screen notification fires, the APNs pipeline is broken. See the troubleshooting section below.

## Access

ntfy is reachable at three URLs, each for a different purpose:

| URL | Purpose | Who uses it |
|-----|---------|-------------|
| `http://ntfy:80` | Internal publish from Uptime Kuma | Uptime Kuma over Docker network |
| `http://<container-ip>:2586` | Local admin from the LXC host | SSH troubleshooting |
| `https://ntfy.example.com` | Public web UI and iOS app endpoint | The phone, the browser |

The public URL is the one that matters for everyday use. The internal Docker address is what Uptime Kuma uses so that alerts keep working even if the tunnel drops. The LXC host port is the last-resort path when something is broken at the network layer.

## Security

Public means reachable, not open. The `/v1/health` endpoint, the homepage, and `/v1/config` return data without authentication. Everything else requires a login because of `auth-default-access: deny-all`:

| Endpoint | Auth required | Returns |
|----------|---------------|---------|
| `GET /` | No | HTML shell of the web UI |
| `GET /v1/health` | No | `{"healthy":true}` |
| `GET /v1/config` | No | Server config, no secrets |
| `GET /homelab-alerts/json?poll=1` | Yes | Returns 403 without auth |
| `POST /homelab-alerts` | Yes | Returns 403 without auth |
| `GET /homelab-alerts/auth` | Yes | Returns 403 without auth |

The shape is the same as `github.com` or `ntfy.sh` itself: the shell is public so that users can log in, but the actual data lives behind auth. A passer-by can see that ntfy is running and learn nothing actionable from it.

Three hardening steps beyond the defaults:

- **Regular updates.** ntfy moves fast. `docker compose pull && docker compose up -d` once a month keeps the container on a recent release.
- **Cloudflare rate limiting.** The free Cloudflare plan already throttles abusive traffic patterns. A more aggressive rate-limit rule on the login endpoint is a one-click add if brute force attempts start showing up in the logs.
- **Monitor the topic.** Uptime Kuma itself watches `https://ntfy.example.com/v1/health`. If the public endpoint stops responding, an alert fires through… ntfy, which creates an amusing circular dependency. For true breakage notifications, the built-in web UI notification on Uptime Kuma is the fallback.

## Troubleshooting iOS push

When push notifications stop working, these are the things to check, in order of likelihood:

**1. Topic name match.**
The topic name in Uptime Kuma and the topic subscribed in the iOS app must be identical. A typo (`home-alerts` instead of `homelab-alerts`) results in no errors anywhere, just silence.

**2. `base-url` match between config and env.**
`NTFY_BASE_URL` in the docker-compose file and `base-url` in `server.yml` must be identical strings. Environment variables override the config file. The upstream pattern computes a SHA256 hash from the base URL. A mismatch between the server and the iOS app (even a different subdomain) means different hashes, and pushes vanish.

**3. Outbound to `ntfy.sh`.**
Verify the container can reach the upstream:

```bash
docker exec ntfy wget -qO- https://ntfy.sh/v1/health
```

Should return `{"healthy":true}`. If not, outbound network is blocked somewhere.

**4. Debug logs for the poll request.**
Temporarily add `log-level: DEBUG` to `server.yml` and restart the container. Publish a test message and grep the logs:

```bash
docker logs ntfy 2>&1 | grep "Publishing poll request"
```

If the line appears, the server side is working. If it does not, the upstream config is wrong.

**5. iOS re-registration.**
After changing `base-url`, the iOS app has to re-register with the upstream using the new hash. Delete the subscription, force-quit the app, reopen it, and subscribe again. In stubborn cases, delete the app entirely and reinstall.

**6. iOS notification settings.**
Check that Scheduled Summary is off for ntfy (Settings → Notifications → ntfy) and that Immediate Delivery is enabled. Scheduled Summary batches notifications and delivers them at fixed times, which is the opposite of what you want for alerts.

**7. Control test with a public topic.**
Subscribe to a fresh public topic on `https://ntfy.sh` (no auth, no upstream) and send a test. If that push arrives, the iOS side is healthy and the problem is in the self-hosted config. If it also fails, the issue is with the device, not the server.

## Backup

The `ntfy-cache` volume holds the SQLite user database, all tokens, and the cached messages. The `ntfy-etc` volume holds the server config. Both are captured by the weekly LXC backup job.

Losing `ntfy-cache` means recreating the admin user and reissuing tokens to every publisher. Losing `ntfy-etc` means rewriting `server.yml`. Neither is catastrophic, but the backup is cheap and the restore is trivial, so there is no reason to skip it.
