# Pihole with dot, doh, updatelists, and cache domains for lancache
Official pihole docker with DoT (DNS over TLS), DoH (DNS over HTTPS), jacklul/pihole-updatelists, and uklans/cache-domains configured to check and update daily if needed. 

Multi-arch image built for amd64, 386, arm64, arm/v7, and arm/v6.

**Uses the proven jacklul/pihole-updatelists approach** - modifies Pi-hole's startup scripts for maximum compatibility with Raspberry Pi and other platforms.

## Usage:
For docker parameters, refer to [official pihole docker readme](https://github.com/pi-hole/pi-hole).

### Docker Compose Setup

```yaml
version: '3.8'

services:
  pihole:
    container_name: pihole
    image: mwatz/pihole-dot-dnsproxy-updatelists-lancache-cache-domains:latest
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
      # CRONTAB_STRING: Custom cron schedule (default: random time 3-4 AM Saturday)
    volumes:
      - './etc-pihole:/etc/pihole'
      - './etc-dnsmasq.d:/etc/dnsmasq.d'
      - './config:/config'
      - './cache-domains:/etc/cache-domains'
    cap_add:
      - NET_ADMIN
    restart: unless-stopped
```

**✅ Ready to go!** Just run: `docker-compose up -d`

**Optional - Pre-create directories (only if you want to avoid permission warnings):**
```bash
# Create directories
mkdir -p ./etc-pihole ./etc-dnsmasq.d ./config ./cache-domains/config

# Set ownership to UID/GID 1000 (what the container uses)
sudo chown -R 1000:1000 ./etc-pihole ./etc-dnsmasq.d ./config ./cache-domains
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
- On scheduled cron run (default: 3-4 AM Saturday)
- Manually: `docker exec pihole pihole-updatelists`

**lancache config.json** (./cache-domains/config/config.json):
```json
{
  "ips": {
    "generic": "10.0.0.100"
  },
  "cache_domains": {
    "default": "generic"
  }
}
```
**⚠️ IMPORTANT:** Replace `10.0.0.100` with your actual Lancache server IP address!

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
  * Configure via **environment variables** (recommended) OR mount config file
  * Environment variables: `BLOCKLISTS_URL`, `ALLOWLISTS_URL`, `WHITELIST_URL`, `REGEX_WHITELIST_URL`, `BLACKLIST_URL`, `REGEX_BLACKLIST_URL`
  * Config file: `./pihole-updatelists/pihole-updatelists.conf` (if not using env vars)
  * Example includes: Firebog tick lists, DeveloperDan tracking, AnudeepND whitelists, mmotti regex & whitelist, StevenBlack hosts
  * Multiple URLs per variable: separate with spaces (env vars) or newlines (config file)
  * **Runs automatically on container start/restart** (waits for FTL readiness)
  * Also runs via cron (default: 3-4 AM Saturday, configurable via `CRONTAB_STRING` env var)
  * Manual run: `docker exec pihole pihole-updatelists`
* **Lancache (Cache Domains)**
  * Config: `./cache-domains/config/config.json` - **Set your Lancache server IP here!**
  * Points Pi-hole to your Lancache server for gaming CDNs (Steam, Epic, Xbox, etc.)
  * Generates ~26 dnsmasq config files in `/etc/dnsmasq.d/` (one per CDN service)
  * Example config: [stuff/config.json](stuff/config.json)
  * **Runs automatically on container start/restart** (clones/updates repo, generates configs, waits for FTL, then reloads DNS)
  * **Also runs daily via cron** at random minute during 4:XX AM to check for upstream updates
  * Manual run: `docker exec pihole bash /usr/local/bin/_cachedomainsonboot.sh`
  * On first start: clones uklans/cache-domains repo and generates ~26 dnsmasq configs
  * On restart: checks for upstream changes and regenerates if needed
  * Verify configs: `docker exec pihole ls /etc/dnsmasq.d/` (should show steam.conf, epicgames.conf, etc.)
* **DNSProxy (DoT/DoH encryption)**
  * Config: `./config/dnsproxy.yml`
  * Runs on 127.0.0.1:5054 inside container
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
  * /etc/pihole-updatelists.conf → pihole-updatelists config file (can also use environment variables)
  * /etc/cache-domains/config/config.json → cache-domains configuration
* Multi-arch support
  * Builds for amd64, arm64, arm32/v7, arm32/v6.

## Troubleshooting

### Permission Errors (Rare - mostly affects custom UID/GID setups)

The container automatically creates config files with correct permissions. If you still see errors like `Permission denied`, `unable to open database`, or `Operation not permitted`:

1. **Stop the container:**
   ```bash
   docker-compose down
   ```

2. **Fix existing directory permissions:**
   ```bash
   # Set ownership to match container (default UID:GID is 1000:1000)
   sudo chown -R 1000:1000 ./etc-pihole ./etc-dnsmasq.d
   sudo chown -R 1000:1000 ./config ./cache-domains
   ```

3. **Or use your own UID/GID** by adding to environment variables:
   ```yaml
   environment:
     - PIHOLE_UID=1001  # Your user's UID (check with: id -u)
     - PIHOLE_GID=1001  # Your user's GID (check with: id -g)
   ```

4. **Start the container:**
   ```bash
   docker-compose up -d
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

**Fix:** Ensure no quotes around the value in your compose file:
```yaml
environment:
  FTLCONF_dns_upstreams: 127.0.0.1#5054  # Correct (no quotes)
  # NOT: FTLCONF_dns_upstreams: '127.0.0.1#5054'  # Wrong for lists
```

### DNS Not Working

- Check if DNSProxy is running: `docker exec pihole netstat -tuln | grep 5054`
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
       * Special thanks to oct8l for scripting guidance: Guide

* If you like my work, [a donation to my hot tamales fund](https://paypal.me/mwatz1234) is very much appreciated.
  
[![Donate](https://github.com/mwatz1234/pihole-dot-doh-updatelists/blob/master/donate-button-small.png)](https://paypal.me/mwatz1234)
