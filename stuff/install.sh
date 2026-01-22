#!/bin/bash
set -e

########################################
# Install dnsproxy (DoT + DoH fallback)
########################################

DNSPROXY_VERSION="0.71.2"
ARCH=$(dpkg --print-architecture)

case "$ARCH" in
  amd64) DNSPROXY_ARCH="amd64" ;;
  arm64) DNSPROXY_ARCH="arm64" ;;
  armhf) DNSPROXY_ARCH="armv7" ;;
  i386)  DNSPROXY_ARCH="386" ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

echo "Installing dnsproxy for architecture: $DNSPROXY_ARCH"

curl -sL \
  https://github.com/AdguardTeam/dnsproxy/releases/download/v${DNSPROXY_VERSION}/dnsproxy-linux-${DNSPROXY_ARCH}-v${DNSPROXY_VERSION}.tar.gz \
  -o /tmp/dnsproxy.tar.gz

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
killall -9 dnsproxy
EOF

chmod +x /etc/services.d/dnsproxy/run
chmod +x /etc/services.d/dnsproxy/finish

########################################
# Cleanup
########################################

apt-get -y autoremove \
    && apt-get -y autoclean \
    && apt-get -y clean \
    && rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists/*

########################################
# Lancache / cache-domains section (patched)
########################################

mkdir -p /etc/s6-overlay/s6-rc.d/_cachedomainsonboot
mkdir -p /etc/s6-overlay/s6-rc.d/_cachedomainsonboot/dependencies.d
echo "" > /etc/s6-overlay/s6-rc.d/_cachedomainsonboot/dependencies.d/pihole-FTL
echo "oneshot" > /etc/s6-overlay/s6-rc.d/_cachedomainsonboot/type

cat << 'EOF' > /etc/s6-overlay/s6-rc.d/_cachedomainsonboot/up
#!/command/execlineb
background { bash -e /usr/local/bin/_cachedomainsonboot.sh }
EOF

cat << 'EOF' > /usr/local/bin/_cachedomainsonboot.sh
#!/bin/bash
set -e

WORKDIR=/root
cd $WORKDIR

# Clone repo only if missing
if [ ! -d "$WORKDIR/cache-domains" ]; then
    git clone https://github.com/uklans/cache-domains.git
fi

# Copy domain files and scripts
mkdir -p /etc/cache-domains/
cp $(find "$WORKDIR/cache-domains" -name "*.txt" -o -name "cache_domains.json") /etc/cache-domains

mkdir -p /etc/cache-domains/scripts/
cp "$WORKDIR/cache-domains/scripts/create-dnsmasq.sh" /etc/cache-domains/scripts/
chmod +x /etc/cache-domains/scripts/create-dnsmasq.sh

# Copy config
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
