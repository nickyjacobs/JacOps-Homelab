# Hardening

🇬🇧 [English](02-hardening.md) | 🇳🇱 Nederlands

Dit document beschrijft de security hardening van het Proxmox cluster. Het werk is uitgevoerd in negen fases tijdens een enkele sessie. Elke fase richt zich op een specifiek aanvalsoppervlak.

## Uitgangspunt

Het cluster was functioneel maar niet gehard. De eerste audit vond:

- Root SSH login met wachtwoordauthenticatie ingeschakeld
- Geen brute-force bescherming (fail2ban niet geinstalleerd)
- Proxmox firewall uitgeschakeld op beide nodes
- Geen tweefactorauthenticatie op de webinterface
- Beveiligingsupdates weken achter (waaronder OpenSSH en OpenSSL)
- Kernel-level netwerkhardening afwezig (ICMP redirects geaccepteerd)
- Onnodige services actief (rpcbind, postfix)
- Geen geautomatiseerde backups geconfigureerd
- Geen automatische security patching

Geen van deze punten is ongebruikelijk voor een vers geinstalleerd Proxmox cluster. De standaardinstellingen geven voorrang aan toegankelijkheid boven beveiliging. Dit document beschrijft wat er veranderde en waarom.

## Fase 1: Systeemupdates

Beide nodes zijn bijgewerkt naar de nieuwste packages, inclusief een kernelupgrade en Proxmox-versiealignment. Voor de update liep een node twee minorversies achter op de ander. Na de update draaien beide dezelfde Proxmox- en kernelversie.

De update bevatte beveiligingspatches voor OpenSSH, OpenSSL, corosync en diverse andere packages. Een gecoordineerde reboot van beide nodes volgde om de nieuwe kernel te activeren.

Applicatiecontainers zijn ingesteld op `onboot: 1` zodat ze automatisch herstarten na een reboot. Dit was voorheen niet geconfigureerd, waardoor services bleven liggen totdat iemand het opmerkte.

## Fase 2: SSH hardening

Drie wijzigingen verkleinen het SSH-aanvalsoppervlak.

**Dedicated admin user.** Een non-root gebruiker met sudo-toegang vervangt directe root login voor dagelijks gebruik. Root login is beperkt tot public key authenticatie (`PermitRootLogin prohibit-password`). Een aanvaller die het root-wachtwoord steelt kan hierdoor niet via SSH inloggen. Daarvoor is het private key bestand nodig.

**Alleen key-authenticatie.** Wachtwoordauthenticatie is volledig uitgeschakeld (`PasswordAuthentication no`). Dit elimineert brute-force aanvallen op SSH als categorie. De enige manier om binnen te komen is het bezit van een geautoriseerde private key.

**Verminderde blootstelling.** X11 forwarding is uit (onnodig aanvalsoppervlak), het maximum aantal authenticatiepogingen is beperkt tot drie per verbinding, en inactieve sessies worden na vijf minuten zonder activiteit verbroken.

```
# /etc/ssh/sshd_config.d/hardening.conf
PermitRootLogin prohibit-password
PasswordAuthentication no
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
```

## Fase 3: Brute-force bescherming

Fail2ban bewaakt authenticatielogs en bant IP-adressen tijdelijk na herhaalde mislukkingen.

**SSH jail.** Vijf mislukte inlogpogingen binnen tien minuten activeren een ban van een uur. Met key-only authenticatie al ingeschakeld vangt deze jail portscanners en bots die het toch proberen.

**Proxmox web UI jail.** Dezelfde logica toegepast op de Proxmox API daemon. Vijf mislukte web UI loginpogingen vanaf hetzelfde IP resulteren in een ban van een uur. Het filter bewaakt journald op pvedaemon authenticatiefoutmeldingen.

```ini
# /etc/fail2ban/jail.d/proxmox.conf
[proxmox]
enabled = true
port = 8006
filter = proxmox
backend = systemd
maxretry = 5
bantime = 3600
findtime = 600
```

## Fase 4: Proxmox firewall

Proxmox heeft een eigen firewalllaag die op elke node draait, onafhankelijk van de netwerkfirewall op de gateway. Inschakelen voegt defense in depth toe: zelfs als de netwerkfirewall verkeerd geconfigureerd is, dropt de hypervisor nog steeds ongeautoriseerd verkeer.

Het clusterwijde beleid is `DROP` voor inbound verkeer. Outbound verkeer is toegestaan (nodes moeten package repositories en het internet bereiken voor updates).

Toegestaan inbound verkeer:

| Bron | Doel | Protocol | Poort | Reden |
|------|------|----------|-------|-------|
| Management VLAN | Nodes | TCP | 22 | SSH-toegang |
| Management VLAN | Nodes | TCP | 8006 | Web UI toegang |
| VPN subnet | Nodes | TCP | 22, 8006 | Remote beheer |
| Servers VLAN | Nodes | Any | Any | Inter-node clusterverkeer |
| Apps VLAN | Nodes | TCP | 8006 | Monitoring health checks |
| Apps VLAN | Nodes | ICMP | - | Monitoring ping checks |

Al het overige wordt stilzwijgend gedropt. Een apparaat op het Lab- of IoT-VLAN kan de Proxmox management-interface niet bereiken, zelfs niet als de netwerkfirewall het niet blokkeert.

## Fase 5: Kernel hardening

Sysctl-instellingen harden de netwerkstack tegen veelvoorkomende aanvallen.

| Instelling | Waarde | Doel |
|------------|--------|------|
| `accept_redirects` | 0 (IPv4 + IPv6) | Voorkomt ICMP redirect-aanvallen die verkeer omleiden |
| `send_redirects` | 0 | Node moet geen andere hosts redirecten |
| `tcp_syncookies` | 1 | SYN flood bescherming |
| `log_martians` | 1 | Logt pakketten met onmogelijke bronadressen |
| `icmp_echo_ignore_broadcasts` | 1 | Negeert broadcast pings (smurf-aanval mitigatie) |
| `icmp_ignore_bogus_error_responses` | 1 | Negeert misvormde ICMP foutmeldingen |
| `rp_filter` | 2 (loose) | Reverse path filtering, loose modus voor Proxmox-compatibiliteit |

Deze instellingen staan in `/etc/sysctl.d/99-hardening.conf` en overleven reboots.

## Fase 6: Tweefactorauthenticatie

TOTP is ingeschakeld voor het root-account op de Proxmox web UI. Inloggen vereist zowel het wachtwoord als een zescijferige code uit een authenticator-app. Dit beschermt tegen diefstal van credentials: een gestolen wachtwoord alleen is niet voldoende om de management-interface te bereiken.

Herstelcodes worden offline bewaard voor het geval het authenticatorapparaat verloren gaat.

## Fase 7: Opruimen van services

Twee onnodige services zijn uitgeschakeld.

**rpcbind** luistert op poort 111 op alle interfaces. Het is een vereiste voor NFS, dat het cluster niet gebruikt. Actief laten stelt een onnodige netwerkservice bloot. Uitgeschakeld op beide nodes.

**postfix** draaide als lokale mail transport agent. Het cluster verstuurt geen e-mailnotificaties. Geen andere service is afhankelijk van lokale mailaflevering. Uitgeschakeld op beide nodes.

## Fase 8: Geautomatiseerde backups

Een geplande backupjob draait wekelijks op zondag om 03:00. Snapshot mode wordt gebruikt zodat draaiende containers niet onderbroken worden.

| Instelling | Waarde |
|------------|--------|
| Schema | Zondag 03:00 |
| Storage | Bulk HDD op Node 1 |
| Compressie | zstd |
| Retentie | 4 wekelijkse backups |
| Scope | Alle VMs en containers |

De backup dekt configuratieherstel en onbedoeld verwijderen. Het venster van vier weken betekent dat er altijd een known-good snapshot beschikbaar is om naar terug te keren.

## Fase 9: Automatische security patching

Unattended-upgrades is geinstalleerd en geconfigureerd om automatisch Debian-beveiligingspatches toe te passen. Proxmox-specifieke updates worden uitgesloten van automatische installatie omdat ze breaking changes kunnen bevatten die handmatige beoordeling vereisen.

```
Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${distro_codename}-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
```

Automatische reboots zijn uitgeschakeld. Beveiligingspatches die een reboot vereisen (kernelupdates) worden handmatig toegepast tijdens een onderhoudsvenster.

## Resultaat

Na alle negen fases heeft het cluster:

- Key-only SSH met een dedicated admin user
- Brute-force bescherming op SSH en de webinterface
- Een host-level firewall met deny-by-default beleid
- Geharde kernel-netwerkinstellingen
- Tweefactorauthenticatie op de management-interface
- Geen onnodige services die luisteren
- Geautomatiseerde wekelijkse backups met vier weken retentie
- Automatische Debian security patching

Deze maatregelen stapelen op de netwerkniveau-verdedigingen beschreven in de [netwerksectie](../network/). De combinatie betekent dat een aanvaller de zone-based firewall, de host-level firewall, key-based SSH-authenticatie en TOTP-beveiligde webauthenticatie moet omzeilen voordat iets bruikbaars bereikt wordt.
