#!/bin/bash
set -ex  # Print commands and exit on first failure

########################################
# Detect target platform (for GitHub Actions buildx)
########################################
: "${TARGETPLATFORM:=$(uname -m)}"

case "$TARGETPLATFORM" in
  linux/amd64|x86_64) DNSPROXY_ARCH="amd64" ;;
  linux/arm64|aarch64) DNSPROXY_ARCH="arm64" ;;
  linux/arm/v7|armv7l) DNSPROXY_ARCH="armv7" ;;
  linux/arm/v6|armv6l) DNSPROXY_ARCH="armv6" ;;
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
DNSPROXY_VERSION=$(curl -s -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/AdguardTeam/dnsproxy/releases \
  | grep -E '"tag_name": "v[0-9]+\.[0-9]+\.[0-9]+"' \
  | head -n 1 \
  | grep -Po 'v[0-9]+\.[0-9]+\.[0-9]+')

if [ -z "$DNSPROXY_VERSION" ]; then
    echo "Failed to detect latest dnsproxy release"
    exit 1
fi

DNSPROXY_VERSION_NUMBER="${DNSPROXY_VERSION#v}"
echo "Latest stable dnsproxy release: $DNSPROXY_VERSION_NUMBER"

# Download and extract
curl -sL \
  "https://github.com/AdguardTeam/dnsproxy/releases/download/${DNSPROXY_VERSION_NUMBER}/dnsproxy-linux-${DNSPROXY_ARCH}-v${DNSPROXY_VERSION_NUMBER}.tar.gz" \
  -o /tmp/dnsproxy.tar.gz

if [ ! -f "/tmp/dnsproxy.tar.gz" ]; then
    echo "dnsproxy tarball missing!"
    exit 1
fi

tar -xzf /tmp/dnsproxy.tar.gz -C /tmp
cp /tmp/linux-${DNSPROXY_ARCH}/dnsproxy /usr/local/bin/dnsproxy
chmod +x /usr/local/bin/dnsproxy

########################################
# Default dnsproxy config
########################################
mkdir -p /config
cp -n /temp/dnsproxy.yml /config/dnsproxy.yml

########################################
# s6 service for dnsproxy
########################################
mkdir -p /etc/services.d/dnsproxy

cat << 'EOF' > /etc/services.d/dnsproxy/run
#!/bin/bash
s6-echo "Starting dnsproxy (DNS-over-TLS + DoH fallback)"
exec /usr/local/bin/dnsproxy --config-path=/config/dnsproxy.yml
EOF

cat << 'EOF' > /etc/services.d/dnsproxy/finish
#!/bin/bash
s6-echo "Stopping dnsproxy"
killall -9 dnsproxy || true
EOF

chmod +x /etc/services.d/dnsproxy/run
chmod +x /etc/services.d/dnsproxy/finish

########################################
# Cleanup temporary files
########################################
rm -rf /tmp/* /var/tmp/*

########################################
# Lancache / cache-domains setup
########################################
mkdir -p /etc/s6-overlay/s6-rc.d/_cachedomainsonboot
mkdir -p /etc/s6-overlay/s6-rc.d/_cachedomainsonboot/dependencies.d
echo "" > /etc/s6-overlay/s6-rc.d/_cachedomainsonboot/dependencies.d/pihole-FTL
echo "oneshot" > /etc/s6-overlay/s6-rc.d/_cachedomainsonboot/type

cat << 'EOF' > /etc/s6-overlay/s6-rc.d/_cachedomainsonboot/up
#!/command/execlineb
background { bash -e /usr/local/bin/_cachedomainsonboot.sh }
EOF

# cache-domains boot script
cat << 'EOF' > /usr/local/bin/_cachedomainsonboot.sh
#!/bin/bash
set -ex

WORKDIR=/root
cd $WORKDIR

# Clone repo if missing
if [ ! -d "$WORKDIR/cache-domains" ]; then
    git clone https://github.com/uklans/cache-domains.git
fi

# Pull latest updates
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

# Copy domain files
mkdir -p /etc/cache-domains/
cp $(find "$WORKDIR/cache-domains" -name "*.txt" -o -name "cache_domains.json") /etc/cache-domains

# Copy scripts
mkdir -p /etc/cache-domains/scripts/
cp "$WORKDIR/cache-domains/scripts/create-dnsmasq.sh" /etc/cache-domains/scripts/
chmod +x /etc/cache-domains/scripts/create-dnsmasq.sh

# Copy user config
mkdir -p /etc/cache-domains/config
cp -n /temp/config.json /etc/cache-domains/config/
rm -f /etc/cache-domains/scripts/config.json
ln -sf /etc/cache-domains/config/config.json /etc/cache-domains/scripts/config.json

# Generate dnsmasq files
cd /etc/cache-domains/scripts
bash ./create-dnsmasq.sh > /dev/null 2>&1

# Copy to Pi-hole
cp -r /etc/cache-domains/scripts/output/dnsmasq/*.conf /etc/dnsmasq.d/

# Reload Pi-hole FTL
pihole restartdns reload || killall -HUP pihole-FTL
EOF

chmod +x /usr/local/bin/_cachedomainsonboot.sh

# Post-FTL dependency
mkdir -p /etc/s6-overlay/s6-rc.d/_postFTL/dependencies.d
echo "" > /etc/s6-overlay/s6-rc.d/_postFTL/dependencies.d/_cachedomainsonboot

# Cron job for cache-domains updates
if [ ! -f "/etc/cron.d/cache-domains" ]; then
cat << 'EOF' > /etc/cron.d/cache-domains
# cache-domains Updater by mwatz1234
# https://github.com/mwatz1234/pihole-dot-doh-updatelists-lancache-cache-domains

#30 4 * * * root /usr/local/bin/lancache-dns-updates.sh
EOF
# Randomize minute
sed "s/#30 /$((1 + RANDOM % 58)) /" -i /etc/cron.d/cache-domains
fi

echo "dnsproxy + cache-domains installation complete"
