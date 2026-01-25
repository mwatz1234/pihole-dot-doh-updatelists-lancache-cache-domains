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
      - "443:443/tcp"
      - "53:53/tcp"
      - "53:53/udp"
      - "80:80/tcp"
      - "853:853/tcp"
      - "853:853/udp"
    environment:
      - FTLCONF_LOCAL_IPV4=<IP of host>
      - TZ=America/Los_Angeles
      - WEBPASSWORD=<Password>
      - PIHOLE_DNS_=127.0.0.1#5054
      - DNSSEC=true
      # pihole-updatelists configuration (optional - can also use config file)
      - BLOCKLISTS_URL=https://v.firebog.net/hosts/lists.php?type=tick
      - REGEX_BLACKLIST_URL=https://raw.githubusercontent.com/mmotti/pihole-regex/master/regex.list
    volumes:
      - './etc/pihole:/etc/pihole/:rw'
      - './etc/dnsmasq:/etc/dnsmasq.d/:rw'
      - './etc/config:/config/:rw'
      - './etc/updatelists/pihole-updatelists.conf:/etc/pihole-updatelists.conf:rw'
      - './etc/lancache/config.json:/etc/cache-domains/config/config.json:rw'
    restart: unless-stopped
```

### Configuration Files:

**pihole-updatelists.conf** (./etc/updatelists/pihole-updatelists.conf):
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

**lancache config.json** (./etc/lancache/config.json):
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
Replace `10.20.30.40` with your LanCache server IP.

### Notes:
* **Pi-hole Updatelists**
  * Configure via environment variables (shown above) OR mount a config file
  * Environment variables: `BLOCKLISTS_URL`, `ALLOWLISTS_URL`, `WHITELIST_URL`, `REGEX_WHITELIST_URL`, `BLACKLIST_URL`, `REGEX_BLACKLIST_URL`
  * Config file method: Mount `pihole-updatelists.conf` to `/etc/pihole-updatelists.conf`
  * Recommended lists shown in example above (Firebog tick lists + mmotti regex)
  * Runs automatically on a schedule (configurable via `CRONTAB_STRING` env var)
* Lancache config
  * Create the lancache folder and config.json before starting the container.
  * This container points Pi-hole to your already configured Lancache server for configured CDNs.
  * Example config: stuff/config.json
* Encrypted DNS
  * dnsproxy runs inside the container on 127.0.0.1#5054.
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
  * _cachedomainsonboot ensures that cache-domains are copied and converted to dnsmasq configs on startup.
  * lancache-dns-updates.sh runs daily via cron to pull updates from uklans/cache-domains.
  * Idempotent: running multiple times does not break configs or overwrite manually adjusted files.
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
