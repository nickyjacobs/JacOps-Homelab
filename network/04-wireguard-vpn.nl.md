# WireGuard VPN

🇳🇱 Nederlands | 🇬🇧 [English](04-wireguard-vpn.md)

Dit document behandelt het remote access-pad naar de homelab. De [zone-based firewall](03-zone-firewall.nl.md) houdt het verkeer tussen VLANs aan de LAN-kant onder controle. WireGuard trekt dat model door naar remote clients, zonder een management interface naar het publieke internet te openen.

## Waarom WireGuard

De homelab heeft om twee redenen remote toegang nodig: beheerwerk op Proxmox en de UniFi controller van buitenaf, en af en toe toegang tot labdiensten tijdens het reizen. Een van die interfaces rechtstreeks op de WAN openzetten is geen optie. Dan blijft een VPN over.

WireGuard wint het voor een kleine homelab van OpenVPN en IPsec. De config is kort genoeg om in één keer door te lezen, de handshake is snel en het UDP-only design maakt NAT traversal voorspelbaar. UniFi gateways hebben een native WireGuard-server aan boord, dus er is geen extra container om te onderhouden.

De prijs: WireGuard heeft geen ingebouwd user management. Elke client krijgt een eigen keypair en een eigen peer-entry op de server. Voor een handvol apparaten is dat prima. Groeit de clientlijst voorbij de tien, dan begint een front-end zoals `wg-easy` pas nut te krijgen.

## DDNS en de WAN-kant

Residentiële ISPs delen dynamische IPv4-adressen uit. Een WireGuard-client heeft een stabiel endpoint nodig, dus het WAN-adres moet een naam hebben die het actuele IP volgt.

Twee opties werken hier:

1. **Provider DDNS.** UniFi ondersteunt een aantal DDNS-providers native. Kies er een, registreer een hostname, wijs de client ernaar.
2. **Zelf beheerde DNS-record.** Heb je al een eigen domein, dan levert een korte cron job die via de registrar API een `A`-record bijwerkt hetzelfde resultaat op, met meer controle.

Beide komen op hetzelfde uit: `vpn.example.com` wijst naar `<WAN_IP>`, en daar wijst elke client config naar. Het WAN-IP zelf staat nooit in een clientbestand, waardoor de configs bruikbaar blijven als het IP verandert.

## Serverconfiguratie

Op de UniFi gateway draait de WireGuard-server standaard op UDP-poort `51820`. De enige inbound WAN-regel die er moet bestaan, laat `UDP 51820` van `any` naar de gateway toe. De rest blijft dicht.

| Setting | Waarde | Reden |
|---------|--------|-------|
| Listen poort | UDP 51820 | Standaard, makkelijk te onthouden |
| VPN subnet | `10.0.90.0/24` | Eigen range, past bij de VPN-zone |
| DNS richting clients | Interne resolver | Split-horizon namen lossen correct op |
| MTU | 1420 | Veilige default, voorkomt fragmentatie bij de meeste ISPs |

Het VPN-subnet landt in de ingebouwde `VPN`-zone uit het [zone-document](03-zone-firewall.nl.md). Daar staan de allow-regels voor Mgmt, Servers en Apps al. Extra firewallwerk is niet nodig zodra de zoneregels er staan.

## Split tunnel versus full tunnel

De keuze draait om wat de client moet doen met verkeer dat niets met de homelab te maken heeft.

**Split tunnel** stuurt alleen verkeer voor de homelab-subnets door de VPN. De rest, inclusief normaal browsen, verlaat de client rechtstreeks via de lokale internetverbinding. Dit is de default voor dagelijks beheerwerk: snel, weinig bandbreedte op de thuis-WAN, en geen onverwachte latency tijdens videogesprekken.

**Full tunnel** routeert alles door de VPN. Nuttig op vijandige netwerken zoals hotel-WiFi of congresvenues, waar je al het verkeer via de thuisverbinding wilt laten uitgaan. De prijs is bandbreedte en latency.

De keuze zit volledig in de client config, specifiek in de `AllowedIPs`-regel. De server hoeft niet te weten welke modus een client gebruikt.

## Client templates

Beide templates gebruiken placeholders. Vervang de waarden tussen haken voordat je ze in een WireGuard-client importeert.

### Split tunnel template

```ini
[Interface]
PrivateKey = <CLIENT_PRIVATE_KEY>
Address = 10.0.90.2/32
DNS = 10.0.10.1

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
PresharedKey = <PRESHARED_KEY>
Endpoint = vpn.example.com:51820
AllowedIPs = 10.0.10.0/24, 10.0.20.0/24, 10.0.30.0/24
PersistentKeepalive = 25
```

De `AllowedIPs`-lijst van een split tunnel client bevat alleen de interne subnets die de client moet kunnen bereiken. Verkeer naar de rest gaat buiten de tunnel om.

### Full tunnel template

```ini
[Interface]
PrivateKey = <CLIENT_PRIVATE_KEY>
Address = 10.0.90.3/32
DNS = 10.0.10.1

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
PresharedKey = <PRESHARED_KEY>
Endpoint = vpn.example.com:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

`AllowedIPs = 0.0.0.0/0, ::/0` is het enige verschil. Die ene regel vertelt de client dat elk pakket via de tunnel moet.

## Key management

Elke client krijgt:

- Een eigen private key, gegenereerd op de client zelf
- De public key van de server
- Een unieke preshared key, bovenop het keypair als post-quantum verzwaring

Preshared keys zijn optioneel in WireGuard. Ik gebruik ze toch, omdat ze niets kosten en een tweede onafhankelijk secret per peer opleveren. Raakt een apparaat kwijt, dan is het roteren van alleen die peer zijn preshared key op de server genoeg om hem buiten te sluiten, zonder aan andere clients te komen.

Private keys verlaten nooit het apparaat waar ze bij horen. Client configs worden gegenereerd met een placeholder voor de private key, en de echte waarde wordt op het doelapparaat geplakt.

## De tunnel testen

Na het importeren van een client config bevestigt een korte check dat de tunnel werkt en dat de firewallzones zich gedragen zoals verwacht.

- Client kan de gateway bereiken: `ping 10.0.90.1` moet antwoorden.
- Split tunnel client kan de Proxmox web UI op het Servers VLAN openen: toegestaan.
- Split tunnel client opent een publieke website: via het lokale internet, niet door de tunnel.
- Full tunnel client opent een publieke website: verkeer verlaat de thuis-WAN. Een `whatismyip`-service bevestigt het zichtbare IP.
- Client kan de SOC- of Lab-zone niet bereiken: geblokkeerd door de zoneregels.

Die laatste check is de belangrijke. VPN-clients erven de zoneregels, niet andersom. Kan een client bij een zone waar de VPN niets te zoeken heeft, dan klopt de zoneconfig niet, en niet de VPN-config.

## Wat komt hierna

Remote toegang is nu mogelijk zonder een managementpoort naar het internet te openen. Het [cybersecurity hardening-document](05-cybersecurity-hardening.nl.md) voegt de lagen daarbovenop toe: IPS, GeoIP-filtering, versleutelde DNS en de rest van de defensieve houding.
