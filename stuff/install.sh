#!/bin/bash
set -ex  # Print commands and exit on first failure

########################################
# Detect target platform
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

echo "Latest stable dnsproxy release: $DNSPROXY_VERSION"

# Strip leading 'v' for the filename
DNSPROXY_VERSION_NO_V=${DNSPROXY_VERSION#v}

# Correct download URL - dnsproxy uses format: dnsproxy-linux-amd64-v0.78.2.tar.gz (with 'v' prefix)
DNSPROXY_URL="https://github.com/AdguardTeam/dnsproxy/releases/download/${DNSPROXY_VERSION}/dnsproxy-linux-${DNSPROXY_ARCH}-${DNSPROXY_VERSION}.tar.gz"
echo "Downloading $DNSPROXY_URL"

# Download with wget (following redirects)
wget -O /tmp/dnsproxy.tar.gz "$DNSPROXY_URL"

if [ ! -f "/tmp/dnsproxy.tar.gz" ]; then
    echo "ERROR: dnsproxy tarball missing!"
    exit 1
fi

# Verify file size (should be several MB, not an error page)
FILE_SIZE=$(stat -c%s "/tmp/dnsproxy.tar.gz" 2>/dev/null || stat -f%z "/tmp/dnsproxy.tar.gz" 2>/dev/null || echo "0")
if [ "$FILE_SIZE" -lt 100000 ]; then
    echo "ERROR: Downloaded file is too small ($FILE_SIZE bytes), likely an error page"
    head -n 20 /tmp/dnsproxy.tar.gz
    exit 1
fi

# Verify it's a valid tar.gz file
if ! tar -tzf /tmp/dnsproxy.tar.gz > /dev/null 2>&1; then
    echo "ERROR: Downloaded file is not a valid tar.gz archive"
    file /tmp/dnsproxy.tar.gz || true
    head -n 10 /tmp/dnsproxy.tar.gz
    exit 1
fi

# Extract tarball and find the binary
echo "Extracting dnsproxy..."
tar -xzf /tmp/dnsproxy.tar.gz -C /tmp

# Find and copy the dnsproxy binary (it may be in a subdirectory)
DNSPROXY_BIN=$(find /tmp -name "dnsproxy" -type f | head -n 1)
if [ -z "$DNSPROXY_BIN" ]; then
    echo "ERROR: dnsproxy binary not found in archive"
    ls -la /tmp/
    exit 1
fi

cp "$DNSPROXY_BIN" /usr/local/bin/dnsproxy
chmod +x /usr/local/bin/dnsproxy
echo "dnsproxy installed successfully"

########################################
# Default dnsproxy config
########################################
mkdir -p /config
if [ -f /temp/dnsproxy.yml ]; then
    cp -n /temp/dnsproxy.yml /config/dnsproxy.yml
else
    cat << 'EOF' > /config/dnsproxy.yml
bind-address: 0.0.0.0:5053
upstream:
  - tls://1.1.1.1
  - tls://1.0.0.1
log-level: info
EOF
fi

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
rm -rf /tmp/dnsproxy.tar.gz /tmp/dnsproxy

########################################
# Lancache / cache-domains setup
# (kept exactly as your original)
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
cp $(find "$WORKDIR/cache-domains" -name "*.txt" -o -name "cache_domains.json") /etc/cache-domains

mkdir -p /etc/cache-domains/scripts/
cp "$WORKDIR/cache-domains/scripts/create-dnsmasq.sh" /etc/cache-domains/scripts/
chmod +x /etc/cache-domains/scripts/create-dnsmasq.sh

mkdir -p /etc/cache-domains/config
if [ -f /temp/config.json ]; then
    cp -n /temp/config.json /etc/cache-domains/config/
fi
rm -f /etc/cache-domains/scripts/config.json
ln -sf /etc/cache-domains/config/config.json /etc/cache-domains/scripts/config.json

cd /etc/cache-domains/scripts
bash ./create-dnsmasq.sh > /dev/null 2>&1

cp -r /etc/cache-domains/scripts/output/dnsmasq/*.conf /etc/dnsmasq.d/
pihole restartdns reload || killall -HUP pihole-FTL
EOF

chmod +x /usr/local/bin/_cachedomainsonboot.sh

# Post-FTL dependency
mkdir -p /etc/s6-overlay/s6-rc.d/_postFTL/dependencies.d
echo "" > /etc/s6-overlay/s6-rc.d/_postFTL/dependencies.d/_cachedomainsonboot

# Cron job for cache-domains updates (Alpine style)
if ! grep -q 'lancache-dns-updates.sh' /etc/crontabs/root 2>/dev/null; then
    # Randomize minute for the cron job
    RANDOM_MINUTE=$((1 + RANDOM % 58))
    echo "${RANDOM_MINUTE} 4 * * * /usr/local/bin/lancache-dns-updates.sh" >> /etc/crontabs/root
fi

echo "dnsproxy + cache-domains installation complete"
