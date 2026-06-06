#!/bin/bash
set -ex

########################################
# Detect target platform
########################################
: "${TARGETPLATFORM:=$(uname -m)}"

case "$TARGETPLATFORM" in
  linux/amd64|x86_64) DNSPROXY_ARCH="amd64" ;;
  linux/arm64|aarch64) DNSPROXY_ARCH="arm64" ;;
  linux/arm/v7|armv7l) DNSPROXY_ARCH="arm7" ;;
  linux/arm/v6|armv6l) DNSPROXY_ARCH="arm6" ;;
  linux/386|i386) DNSPROXY_ARCH="386" ;;
  *)
    echo "Unsupported platform: $TARGETPLATFORM"
    exit 1
    ;;
esac

echo "Detected architecture: $DNSPROXY_ARCH"

########################################
# Install latest stable dnsproxy
########################################
echo "Fetching latest stable dnsproxy release..."
DNSPROXY_VERSION=$(curl -s --max-time 10 https://api.github.com/repos/AdguardTeam/dnsproxy/releases/latest \
  | grep -Po '"tag_name": *"\K[^"]+' || true)

# Fall back to a known-good version if the API is unavailable (rate-limited, network issue, etc.)
if [ -z "$DNSPROXY_VERSION" ]; then
    DNSPROXY_VERSION="v0.81.4"
    echo "GitHub API unavailable, using fallback version: $DNSPROXY_VERSION"
else
    echo "Latest stable dnsproxy release: $DNSPROXY_VERSION"
fi

DNSPROXY_URL="https://github.com/AdguardTeam/dnsproxy/releases/download/${DNSPROXY_VERSION}/dnsproxy-linux-${DNSPROXY_ARCH}-${DNSPROXY_VERSION}.tar.gz"
echo "Downloading $DNSPROXY_URL"

wget -O /tmp/dnsproxy.tar.gz "$DNSPROXY_URL"

if [ ! -f "/tmp/dnsproxy.tar.gz" ]; then
    echo "ERROR: dnsproxy tarball missing!"
    exit 1
fi

FILE_SIZE=$(stat -c%s "/tmp/dnsproxy.tar.gz" 2>/dev/null || stat -f%z "/tmp/dnsproxy.tar.gz" 2>/dev/null || echo "0")
if [ "$FILE_SIZE" -lt 100000 ]; then
    echo "ERROR: Downloaded file is too small ($FILE_SIZE bytes), likely an error page"
    head -n 20 /tmp/dnsproxy.tar.gz
    exit 1
fi

if ! tar -tzf /tmp/dnsproxy.tar.gz > /dev/null 2>&1; then
    echo "ERROR: Downloaded file is not a valid tar.gz archive"
    exit 1
fi

echo "Extracting dnsproxy..."
tar -xzf /tmp/dnsproxy.tar.gz -C /tmp

DNSPROXY_BIN=$(find /tmp -name "dnsproxy" -type f | head -n 1)
if [ -z "$DNSPROXY_BIN" ]; then
    echo "ERROR: dnsproxy binary not found in archive"
    exit 1
fi

cp "$DNSPROXY_BIN" /usr/local/bin/dnsproxy
chmod +x /usr/local/bin/dnsproxy
rm -rf /tmp/dnsproxy.tar.gz /tmp/linux-*
echo "dnsproxy installed successfully"

########################################
# Store default config templates
# (copied to mounted volumes on first container start if missing)
########################################
mkdir -p /usr/local/share/dnsproxy-defaults
if [ -f /temp/dnsproxy.yml ]; then
    cp /temp/dnsproxy.yml /usr/local/share/dnsproxy-defaults/dnsproxy.yml
else
    cat << 'EOF' > /usr/local/share/dnsproxy-defaults/dnsproxy.yml
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
EOF
fi

mkdir -p /usr/local/share/cache-domains-defaults
if [ -f /temp/config.json ]; then
    cp /temp/config.json /usr/local/share/cache-domains-defaults/config.json
fi

########################################
# _start-dnsproxy.sh
# Injected into start.sh after ftl_config (same injection point as
# pihole-updatelists "config" hook). Volumes are guaranteed mounted at
# this point. Configures /config/dnsproxy.yml via three-tier priority:
#   1. DNSPROXY_UPSTREAM env var — generates dnsproxy.yml from env vars each start
#   2. /config/dnsproxy.yml already exists — use as-is (file-based config)
#   3. Neither — auto-copy from baked-in defaults (Cloudflare Default DoT/DoH)
# Then starts dnsproxy in background on 127.0.0.1:5054.
########################################
cat << 'EOF' > /usr/local/bin/_start-dnsproxy.sh
#!/bin/bash
if [ -n "${DNSPROXY_UPSTREAM}" ]; then
    echo "  [i] DNSPROXY_UPSTREAM env var set — generating /config/dnsproxy.yml"
    mkdir -p /config
    {
        echo "listen-addrs:"
        echo "  - 127.0.0.1"
        echo "listen-ports:"
        echo "  - 5054"
        echo "upstream:"
        for _url in ${DNSPROXY_UPSTREAM}; do
            echo "  - ${_url}"
        done
        echo "bootstrap:"
        _bs="${DNSPROXY_BOOTSTRAP:-1.1.1.1 1.0.0.1 9.9.9.9}"
        for _ip in ${_bs}; do
            echo "  - ${_ip}"
        done
        echo "cache: true"
        echo "timeout: 10s"
    } > /config/dnsproxy.yml
elif [ ! -f /config/dnsproxy.yml ] && [ -f /usr/local/share/dnsproxy-defaults/dnsproxy.yml ]; then
    echo "  [i] Initializing /config/dnsproxy.yml from defaults"
    mkdir -p /config
    cp /usr/local/share/dnsproxy-defaults/dnsproxy.yml /config/dnsproxy.yml
fi
echo "  [i] Starting dnsproxy (DoT/DoH) on 127.0.0.1:5054"
/usr/local/bin/dnsproxy --config-path=/config/dnsproxy.yml >/var/log/dnsproxy.log 2>&1 &
EOF
chmod +x /usr/local/bin/_start-dnsproxy.sh

########################################
# _lancache-cron.sh
# Injected into start.sh before start_cron. Applies LANCACHE_CRONTAB_STRING
# env var override to /crontab.txt before dcron loads it. Same pattern as
# pihole-updatelists "cron" hook which runs at the same point.
########################################
cat << 'EOF' > /usr/local/bin/_lancache-cron.sh
#!/bin/bash
if [ -n "${LANCACHE_CRONTAB_STRING}" ]; then
    echo "  [i] Overriding lancache cron schedule: ${LANCACHE_CRONTAB_STRING}"
    sed -i '/lancache-dns-updates.sh/d' /crontab.txt
    echo "${LANCACHE_CRONTAB_STRING} root PATH=\"/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin\" /usr/local/bin/lancache-dns-updates.sh >/var/log/lancache-dns-updates-cron.log 2>&1" >> /crontab.txt
fi
EOF
chmod +x /usr/local/bin/_lancache-cron.sh

########################################
# _init-cache-domains.sh
# Injected into start.sh after ftl_config (same point as _start-dnsproxy.sh).
# Runs on EVERY container start (not just first start), so LANCACHE_IP env var
# is always applied and /root/cache-domains is always present for the daily
# cron script. Sets lancache IP (three-tier priority), then starts
# _cachedomainsonboot.sh in background; that script polls until FTL is
# ready, generates dnsmasq configs, then calls pihole reloaddns.
#
# Lancache IP priority (highest to lowest):
#   1. LANCACHE_IP env var — always writes config.json, no volume mount needed
#   2. Pre-existing /etc/cache-domains/config/config.json — user-created or previously written
#   3. Baked-in defaults (10.0.0.100 placeholder) — auto-copied on first start
########################################
cat << 'EOF' > /usr/local/bin/_init-cache-domains.sh
#!/bin/bash
if [ -n "${LANCACHE_IP}" ]; then
    echo "  [i] LANCACHE_IP env var set — writing config.json with IP: ${LANCACHE_IP}"
    mkdir -p /etc/cache-domains/config
    printf '{\n  "ips": {\n    "generic": "%s"\n  },\n  "cache_domains": {\n    "default": "generic"\n  }\n}\n' "${LANCACHE_IP}" > /etc/cache-domains/config/config.json
elif [ ! -f /etc/cache-domains/config/config.json ] && [ -f /usr/local/share/cache-domains-defaults/config.json ]; then
    echo "  [i] Initializing cache-domains config from defaults"
    mkdir -p /etc/cache-domains/config
    cp /usr/local/share/cache-domains-defaults/config.json /etc/cache-domains/config/config.json
else
    echo "  [i] Using existing /etc/cache-domains/config/config.json"
fi
echo "  [i] Starting cache-domains initialization in background"
bash /usr/local/bin/_cachedomainsonboot.sh >/var/log/cache-domains-init.log 2>&1 &
EOF
chmod +x /usr/local/bin/_init-cache-domains.sh

########################################
# _cachedomainsonboot.sh
# Clones/updates uklans/cache-domains, generates dnsmasq configs, then
# polls for FTL readiness and calls pihole reloaddns. Runs in background.
########################################
cat << 'EOF' > /usr/local/bin/_cachedomainsonboot.sh
#!/bin/bash
set -e

WORKDIR=/root

cd "$WORKDIR"
if [ ! -d "$WORKDIR/cache-domains" ]; then
    git clone https://github.com/uklans/cache-domains.git
fi

cd "$WORKDIR/cache-domains"
git fetch
HEADHASH=$(git rev-parse HEAD)
UPSTREAMHASH=$(git rev-parse master@{upstream})
if [ "$HEADHASH" != "$UPSTREAMHASH" ]; then
    echo "Upstream repo changed, pulling..."
    git pull
else
    echo "No changes to upstream repo"
fi

mkdir -p /etc/cache-domains/
cp $(find "$WORKDIR/cache-domains" -name "*.txt" -o -name "cache_domains.json") /etc/cache-domains/

mkdir -p /etc/cache-domains/scripts/
cp "$WORKDIR/cache-domains/scripts/create-dnsmasq.sh" /etc/cache-domains/scripts/
chmod +x /etc/cache-domains/scripts/create-dnsmasq.sh

mkdir -p /etc/cache-domains/config
if [ ! -f /etc/cache-domains/config/config.json ] && [ -f /usr/local/share/cache-domains-defaults/config.json ]; then
    cp /usr/local/share/cache-domains-defaults/config.json /etc/cache-domains/config/config.json
fi
rm -f /etc/cache-domains/scripts/config.json
ln -sf /etc/cache-domains/config/config.json /etc/cache-domains/scripts/config.json

cd /etc/cache-domains/scripts
bash ./create-dnsmasq.sh > /dev/null 2>&1
mkdir -p /etc/dnsmasq.d/
cp -r /etc/cache-domains/scripts/output/dnsmasq/*.conf /etc/dnsmasq.d/

echo "Waiting for Pi-hole FTL to be ready..."
max_attempts=300
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if pihole status >/dev/null 2>&1; then
        echo "FTL ready — reloading DNS to apply cache-domains configs"
        pihole reloaddns
        break
    fi
    attempt=$((attempt + 1))
    sleep 2
done

if [ $attempt -eq $max_attempts ]; then
    echo "Warning: FTL did not become ready in time, attempting reload anyway"
    pihole reloaddns || killall -HUP pihole-FTL || true
fi
EOF
chmod +x /usr/local/bin/_cachedomainsonboot.sh

########################################
# Copy lancache daily update script
########################################
if [ -f /temp/lancache-dns-updates.sh ]; then
    cp /temp/lancache-dns-updates.sh /usr/local/bin/lancache-dns-updates.sh
    chmod +x /usr/local/bin/lancache-dns-updates.sh
fi

########################################
# Inject into Pi-hole's startup scripts
# Pattern mirrors jacklul/pihole-updatelists docker install exactly:
#   start.sh injections use sed with \s\+ patterns (BusyBox sed compatible)
#   bash_functions.sh injection hooks after pihole -g
#
# Our injections run at BUILD TIME on the original scripts, then
# pihole-updatelists installer runs AFTER us and adds its own hooks.
# Final order in start.sh:
#   ftl_config
#   bash /usr/local/bin/_start-dnsproxy.sh       <- our inject (after ftl_config)
#   bash /usr/local/bin/_init-cache-domains.sh   <- our inject (after ftl_config)
#   pihole-updatelists.sh config                 <- pihole-updatelists inject
#   install_additional_packages
#   bash /usr/local/bin/_lancache-cron.sh        <- our inject (before start_cron)
#   pihole-updatelists.sh cron                   <- pihole-updatelists inject
#   start_cron                                   <- loads /crontab.txt, starts crond
#
# Final order in bash_functions.sh (inside migrate_gravity, first start only):
#   pihole -g
#   pihole-updatelists.sh run                   <- pihole-updatelists inject
#
# NOTE: _init-cache-domains.sh is intentionally NOT injected after pihole -g.
# It was previously placed there but only ran on first start (when gravity.db
# is absent). Moving it to after ftl_config ensures it runs every start,
# so LANCACHE_IP is always applied and /root/cache-domains is always present.
########################################

# start.sh: start dnsproxy after ftl_config (volumes mounted, config readable)
sed '/^\s\+ftl_config/a bash /usr/local/bin/_start-dnsproxy.sh' -i /usr/bin/start.sh

# start.sh: init cache-domains after ftl_config — EVERY start, not just first.
# Runs after _start-dnsproxy.sh so both are unconditional on each container start.
sed '/bash \/usr\/local\/bin\/_start-dnsproxy.sh/a bash /usr/local/bin/_init-cache-domains.sh' -i /usr/bin/start.sh

# start.sh: apply LANCACHE_CRONTAB_STRING before start_cron loads /crontab.txt
sed '/^\s\+start_cron/i bash /usr/local/bin/_lancache-cron.sh' -i /usr/bin/start.sh

# Verify injections succeeded
grep -q '_start-dnsproxy.sh' /usr/bin/start.sh          || { echo "ERROR: _start-dnsproxy.sh injection failed"; exit 1; }
grep -q '_init-cache-domains.sh' /usr/bin/start.sh      || { echo "ERROR: _init-cache-domains.sh injection failed"; exit 1; }
grep -q '_lancache-cron.sh' /usr/bin/start.sh           || { echo "ERROR: _lancache-cron.sh injection failed"; exit 1; }

echo "dnsproxy + cache-domains installation complete"
