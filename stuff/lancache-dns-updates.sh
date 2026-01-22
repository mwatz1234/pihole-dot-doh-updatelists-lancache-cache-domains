#!/bin/bash
set -e

### Set variables ###
GITSYNCDIR=/root/cache-domains
DNSMASQCONFIG=/etc/cache-domains/config/config.json

# Create a new temp directory
TEMPDIR=$(mktemp -d)
if [ ! -e "$TEMPDIR" ]; then
    >&2 echo "Failed to create temp directory"
    exit 1
fi

# Clean up on exit
trap 'rm -rf "$TEMPDIR"' EXIT

# Fetch latest from git
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

# Copy domain files and scripts to temp
cp $(find "$GITSYNCDIR" -name "*.txt" -o -name "cache_domains.json") "$TEMPDIR"
mkdir -p "$TEMPDIR/scripts"
cp "$GITSYNCDIR/scripts/create-dnsmasq.sh" "$TEMPDIR/scripts/"
chmod +x "$TEMPDIR/scripts/create-dnsmasq.sh"

# Copy config.json to temp
cp "$DNSMASQCONFIG" "$TEMPDIR/scripts/"

# Generate dnsmasq files
cd "$TEMPDIR/scripts"
bash ./create-dnsmasq.sh > /dev/null 2>&1

# Copy to Pi-hole
cp -r "$TEMPDIR/scripts/output/dnsmasq/"*.conf /etc/dnsmasq.d/

# Reload Pi-hole FTL
pihole restartdns reload || killall -HUP pihole-FTL
