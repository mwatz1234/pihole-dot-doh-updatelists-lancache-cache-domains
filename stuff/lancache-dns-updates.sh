#!/bin/bash
set -e

GITSYNCDIR=/root/cache-domains
DNSMASQCONFIG=/etc/cache-domains/config/config.json

# Create temp dir
TEMPDIR=$(mktemp -d)
if [ ! -e "$TEMPDIR" ]; then
    >&2 echo "Failed to create temp directory"
    exit 1
fi
trap 'rm -rf "$TEMPDIR"' EXIT

# Pull latest
cd "$GITSYNCDIR"
git fetch
HEADHASH=$(git rev-parse HEAD)
UPSTREAMHASH=$(git rev-parse master@{upstream})
if [ "$HEADHASH" != "$UPSTREAMHASH" ]; then
    echo "Upstream repo has changed!"
    git pull
else
    echo "No changes to upstream repo!"
    exit
fi

# Copy files to temp
cp $(find "$GITSYNCDIR" -name "*.txt" -o -name "cache_domains.json") "$TEMPDIR"
mkdir -p "$TEMPDIR/scripts"
cp "$GITSYNCDIR/scripts/create-dnsmasq.sh" "$TEMPDIR/scripts/"
chmod +x "$TEMPDIR/scripts/create-dnsmasq.sh"
cp "$DNSMASQCONFIG" "$TEMPDIR/scripts/"

# Generate dnsmasq files
cd "$TEMPDIR/scripts"
bash ./create-dnsmasq.sh > /dev/null 2>&1

# Copy to Pi-hole
cp -r "$TEMPDIR/scripts/output/dnsmasq/"*.conf /etc/dnsmasq.d/

# Reload Pi-hole FTL
pihole restartdns reload || killall -HUP pihole-FTL
