# WireGuard VPN

🇬🇧 English | 🇳🇱 [Nederlands](04-wireguard-vpn.nl.md)

This document covers the remote access path into the homelab. The [zone-based firewall](03-zone-firewall.md) keeps traffic between VLANs under control on the LAN side. WireGuard extends that model to remote clients without exposing any management interface to the public internet.

## Why WireGuard

The homelab needs remote access for two reasons: admin work on Proxmox and the UniFi controller from outside the house, and occasional access to lab services while travelling. Opening any of those interfaces directly on the WAN is a non-starter. That leaves a VPN.

WireGuard wins over OpenVPN and IPsec for a small homelab setup. The config is short enough to read in one sitting, the handshake is fast, and the UDP-only design makes NAT traversal predictable. UniFi gateways ship with a native WireGuard server, so there is no extra container to maintain.

The trade-off: WireGuard has no built-in user management. Every client gets its own keypair and its own peer entry on the server. For a handful of devices that is fine. If the client list ever grows past ten, a front-end like `wg-easy` starts to make sense.

## DDNS and the WAN side

Residential ISPs hand out dynamic IPv4 addresses. A WireGuard client needs a stable endpoint to dial, so the WAN address needs a name that tracks the current IP.

Two options work here:

1. **Provider DDNS.** UniFi has built-in support for several DDNS providers. Pick one, register a hostname, point the client at it.
2. **Self-managed DNS record.** If you already own a domain, a short cron job that updates an `A` record via the registrar API gives the same result with more control.

Both end up at the same place: `vpn.example.com` resolves to `<WAN_IP>`, and that is what every client config points at. The WAN IP itself never shows up in a client file, which keeps the configs portable across IP changes.

## Server configuration

On the UniFi gateway, the WireGuard server lives on UDP port `51820` by default. The only inbound WAN rule that needs to exist is one that allows `UDP 51820` from `any` to the gateway. Everything else stays closed.

| Setting | Value | Reason |
|---------|-------|--------|
| Listen port | UDP 51820 | Default, easy to remember |
| VPN subnet | `10.0.90.0/24` | Dedicated range, matches the VPN zone |
| DNS pushed to clients | Internal resolver | Split-horizon names resolve correctly |
| MTU | 1420 | Safe default, avoids fragmentation over most ISPs |

The VPN subnet lands in the built-in `VPN` zone from the [zone document](03-zone-firewall.md). That is where the allow rules for Mgmt, Servers and Apps live. No extra firewall work is needed once the zone rules are in place.

## Split tunnel versus full tunnel

![WireGuard routing: split vs full tunnel](diagrams/wireguard-routing.svg)

The choice comes down to what the client should do with non-homelab traffic.

**Split tunnel** sends only traffic for the homelab subnets through the VPN. Everything else, including regular browsing, leaves the client directly over its local internet connection. This is the default for daily admin work: fast, low bandwidth on the home WAN, and no surprise latency for video calls.

**Full tunnel** routes everything through the VPN. Useful on hostile networks like hotel WiFi or conference venues, where you want all traffic to exit through the home connection. The cost is bandwidth and latency.

The choice lives entirely in the client config, specifically in the `AllowedIPs` line. The server does not need to know which mode a client is using.

## Client templates

Both templates use placeholders. Replace the bracketed values before importing into a WireGuard client.

### Split tunnel template

```ini
[Interface]
PrivateKey = <CLIENT_PRIVATE_KEY>
Address = 10.0.90.<client-1>/32
DNS = 10.0.10.1

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
PresharedKey = <PRESHARED_KEY>
Endpoint = vpn.example.com:51820
AllowedIPs = 10.0.10.0/24, 10.0.20.0/24, 10.0.30.0/24
PersistentKeepalive = 25
```

The `AllowedIPs` list on a split tunnel client only contains the internal subnets the client needs to reach. Traffic to anything else bypasses the tunnel.

### Full tunnel template

```ini
[Interface]
PrivateKey = <CLIENT_PRIVATE_KEY>
Address = 10.0.90.<client-2>/32
DNS = 10.0.10.1

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
PresharedKey = <PRESHARED_KEY>
Endpoint = vpn.example.com:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

`AllowedIPs = 0.0.0.0/0, ::/0` is the only difference. That single line tells the client to route every packet through the tunnel.

## Key management

Every client gets:

- Its own private key, generated on the client itself
- The server public key
- A unique preshared key, added on top of the keypair for post-quantum hardening

Preshared keys are optional in WireGuard. I use them anyway because they are free and they give a second independent secret per peer. If a device is lost, rotating just that peer's preshared key on the server is enough to lock it out without touching any other client.

Private keys never leave the device they belong to. Client configs are generated with a placeholder for the private key, and the real value gets pasted in on the target device.

## Testing the tunnel

After importing a client config, a short check confirms the tunnel works and the firewall zones behave as expected.

- Client can reach the gateway: `ping 10.0.90.1` should respond.
- Split tunnel client can open the Proxmox web UI on the Servers VLAN: allowed.
- Split tunnel client can open a public website: uses the local internet, not the tunnel.
- Full tunnel client can open a public website: traffic exits through the home WAN. Checking the apparent IP with a `whatismyip` service confirms this.
- Client cannot reach the SOC or Lab zones: blocked by the zone rules.

The last check is the important one. VPN clients inherit the zone rules, not the other way around. If a client can reach a zone the VPN is not supposed to touch, the zone config is wrong, not the VPN config.

## What comes next

Remote access is now possible without exposing any management port to the internet. The [cybersecurity hardening document](05-cybersecurity-hardening.md) adds the layers on top: IPS, GeoIP filtering, encrypted DNS and the rest of the defensive posture.
