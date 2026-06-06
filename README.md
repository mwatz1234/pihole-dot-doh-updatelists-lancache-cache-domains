# Pihole with dot, doh, updatelists, and cache domains for lancache
Official pihole docker with DoT (DNS over TLS), DoH (DNS over HTTPS), jacklul/pihole-updatelists, and uklans/cache-domains configured to check and update daily if needed. 

Multi-arch image built for amd64, 386, arm64, arm/v7, and arm/v6.

**Uses the proven jacklul/pihole-updatelists approach** - modifies Pi-hole's startup scripts for maximum compatibility with Raspberry Pi and other platforms.

## Usage:
For docker parameters, refer to [official pihole docker readme](https://github.com/pi-hole/pi-hole).

### Docker Compose Setup

```yaml
services:
  pihole:
    container_name: pihole
    image: mwatz/pihole-dot-doh-updatelists-lancache-cache-domains:latest
    hostname: pihole
    domainname: pihole.local
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "80:80/tcp"
      - "443:443/tcp"
      - "853:853/tcp"
      - "853:853/udp"
    environment:
      - TZ=America/Los_Angeles
      - FTLCONF_webserver_api_password=<Password>
      - FTLCONF_dns_upstreams=127.0.0.1#5054
      - FTLCONF_dns_listeningMode=all
      # Optional Pi-hole settings
      #- FTLCONF_LOCAL_IPV4=192.168.1.10  # Set to your Pi-hole server's IP
      #- FTLCONF_dns_dnssec=true          # Enable DNSSEC validation
      # pihole-updatelists configuration - automatic blocklist/whitelist management
      # Runs on container start and via cron (default: 3-4 AM Saturday)
      # All variables accept multiple URLs separated by spaces
      # BLOCKLISTS_URL: Remote list URLs containing lists of blocklists (collection lists only, not single blocklists)
      - BLOCKLISTS_URL=https://v.firebog.net/hosts/lists.php?type=tick https://www.github.developerdan.com/hosts/lists/ads-and-tracking-extended.txt
      # WHITELIST_URL: Exact domains to whitelist (handcrafted lists for common false positives)
      - WHITELIST_URL=https://raw.githubusercontent.com/anudeepND/whitelist/master/domains/whitelist.txt https://raw.githubusercontent.com/anudeepND/whitelist/master/domains/referral-sites.txt https://raw.githubusercontent.com/anudeepND/whitelist/master/domains/optional-list.txt https://raw.githubusercontent.com/mmotti/pihole-regex/master/whitelist.list
      # REGEX_BLACKLIST_URL: Regex patterns for advanced blocking
      - REGEX_BLACKLIST_URL=https://raw.githubusercontent.com/mmotti/pihole-regex/master/regex.list
      # Other available variables (uncomment if needed):
      # ALLOWLISTS_URL: Remote list URLs containing lists of allowlists (collection lists only)
      # BLACKLIST_URL: Exact domains to blacklist (handcrafted lists - plain domain format, not hosts files)
      # REGEX_WHITELIST_URL: Regex patterns for whitelisting
      # Scheduling overrides (uncomment to customize):
      # CRONTAB_STRING: pihole-updatelists run schedule (default: random time 3-4 AM Sunday)
      # LANCACHE_CRONTAB_STRING: lancache DNS update schedule (default: 17 4 * * * = 4:17 AM daily)
      # Lancache server IP — env var approach (no /etc/cache-domains volume mount required)
      # All CDN groups (Steam, Epic, Xbox, etc.) are pointed to this single IP
      # Env var takes priority over ./cache-domains/config/config.json when both are set
      #- LANCACHE_IP=192.168.1.10
      # DNSProxy upstream resolver — env var approach (no file editing required)
      # When set: generates /config/dnsproxy.yml on every start; do not hand-edit while active
      # Default (active without this): Cloudflare DoT + DoH (tls://1.1.1.1 + https://cloudflare-dns.com/dns-query)
      #- DNSPROXY_UPSTREAM=tls://1.1.1.1 tls://1.0.0.1 https://cloudflare-dns.com/dns-query
      # Family filter (blocks adult content):
      #- DNSPROXY_UPSTREAM=tls://1.1.1.3 tls://1.0.0.3 https://family.cloudflare-dns.com/dns-query
      # Bootstrap IPs (add 127.0.0.11 for corporate/VPN networks):
      #- DNSPROXY_BOOTSTRAP=1.1.1.1 1.0.0.1 9.9.9.9
    volumes:
      - './etc-pihole:/etc/pihole'           # Required: Pi-hole gravity DB, FTL data, blocklists
      - './etc-dnsmasq.d:/etc/dnsmasq.d'    # Optional: regenerated on every start; mount to inspect on host
      - './config:/config'                   # Recommended: dnsproxy.yml; resets to defaults without this
      - './cache-domains:/etc/cache-domains' # Optional when using LANCACHE_IP env var; Required for file-based lancache config
      # Uncomment to use file-based pihole-updatelists config instead of env vars above:
      # - './pihole-updatelists:/etc/pihole-updatelists/'
    cap_add:
      - NET_ADMIN        # Required: manage network interfaces, firewall rules, and DNS
      - NET_BIND_SERVICE # Required: bind to privileged ports (53, 80, 443)
      - SYS_NICE         # Optional: raise Pi-hole scheduling priority for better DNS latency
      - NET_RAW          # Optional: needed for DHCP functionality (raw packet access)
      - CHOWN            # Optional: set file ownership on mapped volumes
    restart: unless-stopped
```

**✅ Ready to go!** Just run: `docker compose up -d`

**Optional - Pre-create directories (only if you want to avoid permission warnings):**
```bash
# Create directories
mkdir -p ./etc-pihole ./etc-dnsmasq.d ./config ./cache-domains/config

# Set ownership to root (Pi-hole v6 runs as root)
# Docker Desktop on Windows/Mac handles this automatically — Linux hosts only
sudo chown -R root:root ./etc-pihole ./etc-dnsmasq.d ./config ./cache-domains
```

**Note:** The container automatically initializes default config files if they don't exist:
- `/config/dnsproxy.yml` - Created from defaults on first start
- `/etc/cache-domains/config/config.json` - Created from defaults on first start

**Editing config files:**
Edit files directly on your host system in the directories you created (e.g., `./config/dnsproxy.yml`, `./cache-domains/config/config.json`).

### Configuration Files:

---

**dnsproxy.yml** (/config/dnsproxy.yml):
```yaml
listen-addrs:
  - 127.0.0.1      # Internal only — Pi-hole queries it at 127.0.0.1#5054
listen-ports:
  - 5054

upstream:
  # ===== Primary: DNS-over-TLS (DoT) =====

  # Cloudflare Default (fast, privacy-friendly) — active by default
  - tls://1.1.1.1
  - tls://1.0.0.1

  # Cloudflare Family — blocks adult content (replace Default lines above)
  #- tls://1.1.1.3
  #- tls://1.0.0.3

  # Cloudflare Malware/Unsafe — blocks malware and phishing (replace Default lines above)
  #- tls://1.1.1.2
  #- tls://1.0.0.2

  # Quad9 — third-party malware filtering with privacy focus
  #- tls://9.9.9.9

  # ===== Fallback: DNS-over-HTTPS (DoH) =====

  # Cloudflare Default DoH — active by default
  - https://cloudflare-dns.com/dns-query

  # Cloudflare Family DoH (pair with Family DoT above)
  #- https://family.cloudflare-dns.com/dns-query

  # Cloudflare Security DoH (pair with Malware/Unsafe DoT above)
  #- https://security.cloudflare-dns.com/dns-query

  # Quad9 DoH (pair with Quad9 DoT above)
  #- https://dns.quad9.net/dns-query

# Bootstrap IPs used for initial DoH hostname resolution
bootstrap:
  - 1.1.1.1
  - 1.0.0.1
  - 9.9.9.9

cache: true
timeout: 10s
```
Changes require **container restart**.

**pihole-updatelists.conf** (./pihole-updatelists/pihole-updatelists.conf):
> **To activate file-based config:** add volume `./pihole-updatelists:/etc/pihole-updatelists/` to your compose and remove the corresponding env vars — env vars take precedence when both are set.
```conf
; Pi-hole's Lists Updater by Jack'lul
; https://github.com/jacklul/pihole-updatelists
; For a full list of available variables please see the readme.

; Remote list URL containing list of blocklists to import
; URLs to single lists are not supported here!
BLOCKLISTS_URL="https://v.firebog.net/hosts/lists.php?type=tick
https://www.github.developerdan.com/hosts/lists/ads-and-tracking-extended.txt"

; Remote list URL containing list of allowlists to import
; URLs to single lists are not supported here!
ALLOWLISTS_URL=""

; Remote list URL containing exact domains to whitelist
; This is specifically for handcrafted lists only, do not use regular allowlists here!
WHITELIST_URL="https://raw.githubusercontent.com/anudeepND/whitelist/master/domains/whitelist.txt
https://raw.githubusercontent.com/anudeepND/whitelist/master/domains/referral-sites.txt
https://raw.githubusercontent.com/anudeepND/whitelist/master/domains/optional-list.txt
https://raw.githubusercontent.com/mmotti/pihole-regex/master/whitelist.list"

; Remote list URL containing regex rules for whitelisting
REGEX_WHITELIST_URL=""

; Remote list URL containing exact domains to blacklist
; This is specifically for handcrafted lists only, do not use regular blocklists here!
; Must be plain domain format (one domain per line), NOT hosts file format
BLACKLIST_URL=""

; Remote list URL containing regex rules for blacklisting
REGEX_BLACKLIST_URL="https://raw.githubusercontent.com/mmotti/pihole-regex/master/regex.list"
```
Changes take effect:
- **Automatically** on container start/restart (waits for FTL to be ready)
- On scheduled cron run (default: 3-4 AM Sunday)
- Manually: `docker exec pihole pihole-updatelists`

**lancache config.json** (./cache-domains/config/config.json):
> **Easier alternative:** Set `LANCACHE_IP=192.168.1.10` as an environment variable — no config file or volume mount needed.
```json
{
  "ips": {
    "generic": "192.168.1.10"
  },
  "cache_domains": {
    "default": "generic"
  }
}
```
Replace `192.168.1.10` with your actual Lancache server IP. The `"default": "generic"` mapping covers all ~26 CDN groups automatically.

Changes take effect:
- **Automatically** on container start/restart (waits for FTL, then reloads DNS)
- Manually: `docker exec pihole bash /usr/local/bin/_cachedomainsonboot.sh`

### Notes:
* **Pi-hole Updatelists**
  * Configure via **environment variables** (recommended) OR mount config file
  * Environment variables: `BLOCKLISTS_URL`, `ALLOWLISTS_URL`, `WHITELIST_URL`, `REGEX_WHITELIST_URL`, `BLACKLIST_URL`, `REGEX_BLACKLIST_URL`
  * Config file: `./pihole-updatelists/pihole-updatelists.conf` (if not using env vars; requires volume mount `./pihole-updatelists:/etc/pihole-updatelists/`)
  * Example includes: Firebog tick lists, DeveloperDan tracking, AnudeepND whitelists, mmotti regex & whitelist
  * Multiple URLs per variable: separate with spaces (env vars) or newlines (config file)
  * **Runs automatically on container start/restart** (waits for FTL readiness)
  * Also runs via cron (default: 3-4 AM Sunday, configurable via `CRONTAB_STRING` env var)
  * Manual run: `docker exec pihole pihole-updatelists`
* **Lancache (Cache Domains)**
  * Points Pi-hole to your Lancache server for gaming CDNs (Steam, Epic, Xbox, etc.)
  * Generates ~26 dnsmasq config files in `/etc/dnsmasq.d/` (one per CDN service — steam, epic, xbox, blizzard, etc.)
  * **Two ways to set your Lancache server IP (priority order):**
    1. **Env var** `LANCACHE_IP=192.168.1.10` — applied on every restart; `/etc/cache-domains` volume mount not required
    2. **Config file** `./cache-domains/config/config.json` — requires `/etc/cache-domains` volume mount; used when `LANCACHE_IP` env var is not set
  * Config file format (set `generic` to your Lancache IP):
    ```json
    { "ips": { "generic": "192.168.1.10" }, "cache_domains": { "default": "generic" } }
    ```
  * **Runs automatically on container start/restart** (clones/updates repo, generates configs, waits for FTL, then reloads DNS)
  * **Also runs daily via cron** at 4:17 AM by default (set `LANCACHE_CRONTAB_STRING` env var to override)
  * Manual run: `docker exec pihole bash /usr/local/bin/_cachedomainsonboot.sh`
  * On first start: clones uklans/cache-domains repo and generates ~26 dnsmasq configs
  * On restart: checks for upstream changes and regenerates if needed
  * Verify configs: `docker exec pihole ls /etc/dnsmasq.d/` (should show steam.conf, epicgames.conf, etc.)
* **DNSProxy (DoT/DoH)**
  * Runs on 127.0.0.1:5054 inside container; set `FTLCONF_dns_upstreams=127.0.0.1#5054` to route all Pi-hole queries through it (Pi-hole v6 syntax)
  * **Two ways to configure upstream resolvers (priority order):**
    1. **Env var** `DNSPROXY_UPSTREAM` — space-separated upstream URLs; generates `/config/dnsproxy.yml` on every start; no file editing required
       * Optionally pair with `DNSPROXY_BOOTSTRAP` — space-separated bootstrap IPs (default: `1.1.1.1 1.0.0.1 9.9.9.9`; add `127.0.0.11` for corporate/VPN networks)
       * If set, do not hand-edit `/config/dnsproxy.yml` — this env var overwrites it on every start
    2. **Config file** `./config/dnsproxy.yml` — edit on host; used when `DNSPROXY_UPSTREAM` is not set; changes require container restart
  * **Optional filter variants** (set via env var or file):
    * **Default** (`tls://1.1.1.1`, `tls://1.0.0.1`) — fast, privacy-friendly DNS; active by default
    * **Family** (`tls://1.1.1.3`, `tls://1.0.0.3`) — blocks adult content; `DNSPROXY_UPSTREAM=tls://1.1.1.3 tls://1.0.0.3 https://family.cloudflare-dns.com/dns-query`
    * **Malware/Unsafe** (`tls://1.1.1.2`, `tls://1.0.0.2`) — blocks malware and phishing; `DNSPROXY_UPSTREAM=tls://1.1.1.2 tls://1.0.0.2 https://security.cloudflare-dns.com/dns-query`
    * **Quad9** (`tls://9.9.9.9`) — third-party malware + privacy filtering; `DNSPROXY_UPSTREAM=tls://9.9.9.9 https://dns.quad9.net/dns-query`
* Volumes
  * `/etc/pihole` → **Required** — Pi-hole gravity database, FTL config, blocklists; all data lost on restart without this
  * `/config` → **Recommended** — stores `dnsproxy.yml`; without this, dnsproxy resets to Cloudflare Default DoT/DoH on every restart; **Optional** when using `DNSPROXY_UPSTREAM` env var (env var generates the file on every start anyway)
  * `/etc/dnsmasq.d` → **Optional** — lancache dnsmasq configs are regenerated on every startup; mount to inspect files on host
  * `/etc/cache-domains` → **Optional** when using `LANCACHE_IP` env var (env var rewrites config.json on every restart); **Required** when using file-based lancache config
  * `./pihole-updatelists:/etc/pihole-updatelists/` → **Only needed** when using file-based pihole-updatelists config instead of env vars
* Multi-arch support
  * Builds for amd64, arm64, arm32/v7, arm32/v6.

## Troubleshooting

### Permission Errors (Rare)

This image runs as root (Pi-hole v6 default). If you see errors like `Permission denied` or `unable to open database`:

1. **Stop the container:**
   ```bash
   docker compose down
   ```

2. **Fix volume directory permissions:**
   ```bash
   sudo chown -R root:root ./etc-pihole ./etc-dnsmasq.d ./config ./cache-domains
   ```

3. **Start the container:**
   ```bash
   docker compose up -d
   ```

### "Unable to set capabilities for pihole-FTL" / Container Crash-Looping

If you see `ERROR: Unable to set capabilities for pihole-FTL` and the container keeps restarting, this is usually a **non-fatal warning** from Pi-hole's base image. The container should still work.

**If the container actually crashes**, try adding `privileged: true`:

```yaml
services:
  pihole:
    privileged: true
    # ... rest of config
```

**Note:** This image uses the same startup approach as jacklul/pihole-updatelists and should work on all platforms including Raspberry Pi without additional configuration.

### "No DNS upstream set in environment" Error

If you see this despite setting `FTLCONF_dns_upstreams`, the environment variable format might be wrong.

**Fix:** Ensure the env var name and value are correct. Both compose formats work:
```yaml
environment:
  - FTLCONF_dns_upstreams=127.0.0.1#5054  # list format
  # or:
  FTLCONF_dns_upstreams: '127.0.0.1#5054'  # mapping format (quotes are fine)
```

### DNS Not Working

- Check if DNSProxy is running: `docker exec pihole sh -c "ss -tuln | grep 5054"`
- Check if Pi-hole FTL is running: `docker exec pihole pihole status`
- Verify upstream setting: `docker exec pihole pihole-FTL --config dns.upstreams`

### Container Keeps Restarting

- Check logs: `docker logs pihole`
- Ensure port 53 is not in use by another service: `sudo netstat -tulpn | grep :53`

## Credits
  * Pi-hole base image: pihole/pihole:latest
  * dnsproxy (replaces Stubby/Cloudflared) by Adguard: github.com/AdguardTeam/dnsproxy
  * Pi-hole Updatelists: jacklul/pihole-updatelists
  * Cache Domains: uklans/cache-domains
       * Special thanks to oct8l for scripting guidance

* If you like my work, [a donation to my hot tamales fund](https://paypal.me/mwatz1234) is very much appreciated.
  
[![Donate](https://raw.githubusercontent.com/mwatz1234/pihole-dot-doh-updatelists-lancache-cache-domains/master/donate-button-small.png)](https://paypal.me/mwatz1234)
