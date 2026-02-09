# Pihole with dot, doh, updatelists, and cache domains for lancache
Official pihole docker with DoT (DNS over TLS), DoH (DNS over HTTPS), jacklul/pihole-updatelists, and uklans/cache-domains configured to check and update daily if needed. 

Multi-arch image built for amd64, 386, arm64, arm/v7, and arm/v6.

## Usage:
For docker parameters, refer to [official pihole docker readme](https://github.com/pi-hole/pi-hole). Below is an docker compose example.

```
version: '3.8'

services:
  pihole:
    container_name: pihole
    image: mwatz/pihole-dot-dnsproxy-updatelists-lancache-cache-domain:latest
    hostname: pihole
    domainname: pihole.local
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "80:80/tcp"
      - "443:443/tcp"
    environment:
      - TZ=America/Los_Angeles
      - FTLCONF_webserver_api_password=<Password>
      - FTLCONF_dns_upstreams=127.0.0.1#5054
      - FTLCONF_dns_listeningMode=all
      # Optional Pi-hole settings
      #- FTLCONF_LOCAL_IPV4=192.168.1.10  # Set to your Pi-hole server's IP
      #- FTLCONF_dns_dnssec=true          # Enable DNSSEC validation
      # pihole-updatelists configuration (optional - can also use config file)
      - BLOCKLISTS_URL=https://v.firebog.net/hosts/lists.php?type=tick
      - REGEX_BLACKLIST_URL=https://raw.githubusercontent.com/mmotti/pihole-regex/master/regex.list
      #- CRONTAB_STRING=25 2 * * 6
    volumes:
      - './etc-pihole:/etc/pihole'
      - './etc-dnsmasq.d:/etc/dnsmasq.d'
      - './config:/config'
      - './cache-domains:/etc/cache-domains'
      - './pihole-updatelists:/etc/pihole-updatelists'
    cap_add:
      - NET_ADMIN   # Required for proper network operations (recommended)
      - SYS_NICE    # Optional: Gives Pi-hole more processing time
    restart: unless-stopped
```

### Configuration Files:

**dnsproxy.yml** (./config/dnsproxy.yml):
```yaml
listen-addrs:
  - 127.0.0.1
listen-ports:
  - 5054
upstream:
  - tls://1.1.1.1
  - tls://1.0.0.1
  - https://cloudflare-dns.com/dns-query
cache: true
timeout: 10s
```
Changes require **container restart**.

**pihole-updatelists.conf** (./pihole-updatelists/pihole-updatelists.conf):
```conf
; Pi-hole's Lists Updater by Jack'lul
; https://github.com/jacklul/pihole-updatelists
; For a full list of available variables please see the readme.

; Remote list URL containing list of blocklists to import
; URLs to single lists are not supported here!
BLOCKLISTS_URL="https://v.firebog.net/hosts/lists.php?type=tick"

; Remote list URL containing list of allowlists to import
; URLs to single lists are not supported here!
ALLOWLISTS_URL=""

; Remote list URL containing exact domains to whitelist
; This is specifically for handcrafted lists only, do not use regular allowlists here!
WHITELIST_URL=""

; Remote list URL containing regex rules for whitelisting
REGEX_WHITELIST_URL=""

; Remote list URL containing exact domains to blacklist
; This is specifically for handcrafted lists only, do not use regular blocklists here!
BLACKLIST_URL=""

; Remote list URL containing regex rules for blacklisting
REGEX_BLACKLIST_URL="https://raw.githubusercontent.com/mmotti/pihole-regex/master/regex.list"
```
Changes take effect:
- **Automatically** on container start/restart (waits for FTL to be ready)
- On scheduled cron run (default: 3-4 AM Saturday)
- Manually: `docker exec pihole pihole-updatelists`

**lancache config.json** (./cache-domains/config/config.json):
```json
{
  "ips": {
    "generic": "10.20.30.40"
  },
  "cache_domains": {
    "default": "generic"
  }
}
```
Changes take effect:
- **Automatically** on container start/restart (waits for FTL, then reloads DNS)
- Manually: `docker exec pihole bash /usr/local/bin/_cachedomainsonboot.sh`

### Notes:
* **DNSProxy (DoT/DoH)**
  * Config: `./config/dnsproxy.yml`
  * Changes require **container restart**
  * Runs on 127.0.0.1:5054 inside container
  * Supports DoT and DoH upstreams (Cloudflare, Google, Quad9, etc.)
* **Pi-hole Updatelists**
  * Configure via **environment variables** (recommended) OR mount config directory
  * Environment variables: `BLOCKLISTS_URL`, `ALLOWLISTS_URL`, `WHITELIST_URL`, `REGEX_WHITELIST_URL`, `BLACKLIST_URL`, `REGEX_BLACKLIST_URL`
  * Config file: `./pihole-updatelists/pihole-updatelists.conf` (if not using env vars)
  * Recommended lists shown in example above (Firebog tick lists + mmotti regex)
  * **Runs automatically on container start/restart** (waits for FTL readiness)
  * Also runs via cron (default: 3-4 AM Saturday, configurable via `CRONTAB_STRING` env var)
  * Manual run: `docker exec pihole pihole-updatelists`
* **Lancache (Cache Domains)**
  * Config: `./cache-domains/config/config.json`
  * Points Pi-hole to your Lancache server for gaming CDNs
  * Example config: [stuff/config.json](stuff/config.json)
  * **Runs automatically on container start/restart** (clones/updates repo, generates configs, waits for FTL, then reloads DNS)
  * **Also runs daily via cron** at random minute during 4:XX AM to check for upstream updates
  * Manual run: `docker exec pihole bash /usr/local/bin/_cachedomainsonboot.sh`
  * On first start: clones uklans/cache-domains repo and generates ~26 dnsmasq configs
  * On restart: checks for upstream changes and regenerates if needed54.
  * Supports both DoT (TLS) and DoH (HTTPS) upstreams.
  * Cloudflare profiles included:
    * Default → 1.1.1.1 / 1.0.0.1
    * Family → 1.1.1.3 / 1.0.0.3 (blocks adult content)
    * Malware / Security → 1.1.1.2 / 1.0.0.2
    * DoH equivalents → https://cloudflare-dns.com/dns-query, https://family.cloudflare-dns.com/dns-query, https://security.cloudflare-dns.com/dns-query
  * You can adjust /config/dnsproxy.yml to include additional upstreams or change provider order.
* Pi-hole upstream
  * Set PIHOLE_DNS_ to 127.0.0.1#5054 to use encrypted DNSproxy.
  * Pi-hole will automatically forward all queries to the DNSproxy service.
  * No need to set separate DoT/DoH services; dnsproxy handles both.
* Cache Domains / Lancache
  * `_cachedomainsonboot.sh` runs automatically on every container start/restart
  * Clones uklans/cache-domains repo (first start) or checks for updates (restart)
  * Generates dnsmasq configs for ~26 gaming CDNs (Steam, Epic, Origin, Xbox, etc.)
  * Waits for Pi-hole FTL to be ready, then runs `pihole reloaddns` to apply changes
  * `lancache-dns-updates.sh` runs daily via cron (random minute at 4:XX AM) to check for upstream CDN list updates
  * Idempotent: running multiple times does not break configs
* Volumes
  * /config → for dnsproxy config and other persistent config files
  * /etc/pihole → Pi-hole data
  * /etc/dnsmasq.d → Pi-hole dnsmasq overrides
  * /etc/pihole-updatelists → custom blocklists from jacklul/pihole-updatelists
  * /etc/cache-domains/config/config.json → cache-domains configuration
* Multi-arch support
  * Builds for amd64, arm64, arm32/v7, arm32/v6.
* Credits
  * Pi-hole base image: pihole/pihole:latest
  * dnsproxy (replaces Stubby/Cloudflared) by Adguard: github.com/AdguardTeam/dnsproxy
  * Pi-hole Updatelists: jacklul/pihole-updatelists
  * Cache Domains: uklans/cache-domains
       * Special thanks to oct8l for scripting guidance: Guide

* If you like my work, [a donation to my hot tamales fund](https://paypal.me/mwatz1234) is very much appreciated.
  
[![Donate](https://github.com/mwatz1234/pihole-dot-doh-updatelists/blob/master/donate-button-small.png)](https://paypal.me/mwatz1234)
