#---------------------------------------
# Base image
#---------------------------------------
ARG FRM='pihole/pihole:latest'
ARG TAG='latest'
ARG TARGETPLATFORM
FROM ${FRM}

# Re-declare TARGETPLATFORM for use in RUN commands (BuildKit requirement)
ARG TARGETPLATFORM

USER root

#---------------------------------------
# Install dependencies (Alpine-friendly)
#---------------------------------------
RUN apk add --no-cache \
        bash \
        curl \
        wget \
        git \
        sudo \
        nano \
        dcron \
        php \
        php-curl \
        php-intl \
        php-openssl \
        php-pcntl \
        php-posix \
        php-pdo_sqlite

#---------------------------------------
# Copy install scripts & configs
#---------------------------------------
# Make sure your build context has:
# stuff/install.sh
# stuff/dnsproxy.yml
# stuff/config.json
ADD stuff /temp
RUN chmod +x /temp/install.sh

#---------------------------------------
# Run installation (dnsproxy + cache-domains)
#---------------------------------------
RUN TARGETPLATFORM=${TARGETPLATFORM} /bin/bash /temp/install.sh \
    && rm -rf /temp

#---------------------------------------
# Pi-hole updatelists (optional)
#---------------------------------------
RUN wget -O - https://raw.githubusercontent.com/jacklul/pihole-updatelists/master/install.sh | bash -s docker

#---------------------------------------
# Build info
#---------------------------------------
RUN echo "$(date "+%d.%m.%Y %T") Built from ${FRM} with tag ${TAG}" >> /build_date.info

#---------------------------------------
# Custom entrypoint wrapper
#---------------------------------------
RUN cat << 'EOF' > /usr/local/bin/docker-entrypoint-wrapper.sh
#!/bin/bash
# Initialize config files from defaults
if [ ! -f /config/dnsproxy.yml ] && [ -f /usr/local/share/dnsproxy-defaults/dnsproxy.yml ]; then
    echo "Initializing /config/dnsproxy.yml from defaults"
    cp /usr/local/share/dnsproxy-defaults/dnsproxy.yml /config/dnsproxy.yml
fi

if [ ! -f /etc/cache-domains/config/config.json ] && [ -f /usr/local/share/cache-domains-defaults/config.json ]; then
    echo "Initializing /etc/cache-domains/config/config.json from defaults"
    mkdir -p /etc/cache-domains/config
    cp /usr/local/share/cache-domains-defaults/config.json /etc/cache-domains/config/config.json
fi

# Start dnsproxy in the background
echo "Starting dnsproxy (DoT/DoH proxy on 127.0.0.1:5054)"
/usr/local/bin/dnsproxy --config-path=/config/dnsproxy.yml &

# Initialize cache-domains in the background
echo "Initializing cache-domains..."
bash /usr/local/bin/_cachedomainsonboot.sh &

# Add cache-domains cron job after Pi-hole initializes crontab (in background)
(
  sleep 10  # Wait for Pi-hole to create its crontab
  if ! grep -q 'lancache-dns-updates.sh' /etc/crontabs/root 2>/dev/null; then
    RANDOM_MINUTE=$((1 + RANDOM % 58))
    echo "${RANDOM_MINUTE} 4 * * * /usr/local/bin/lancache-dns-updates.sh >/var/log/lancache-dns-updates-cron.log 2>&1" >> /etc/crontabs/root
    echo "Added cache-domains cron job to run daily at 04:${RANDOM_MINUTE}"
  fi
) &

# Run pihole-updatelists after Pi-hole is ready (in background)
(
  echo "Waiting for Pi-hole FTL to be ready before running updatelists..."
  max_attempts=60
  attempt=0
  
  while [ $attempt -lt $max_attempts ]; do
    if pihole status >/dev/null 2>&1; then
      echo "Pi-hole FTL is ready! Running pihole-updatelists..."
      pihole-updatelists.sh run 2>&1 | head -n 20
      break
    fi
    attempt=$((attempt + 1))
    sleep 2
  done
  
  if [ $attempt -eq $max_attempts ]; then
    echo "Warning: Pi-hole FTL did not become ready in time. Skipping updatelists."
  fi
) &

# Call original pihole entrypoint
exec /usr/bin/start.sh "$@"
EOF
RUN chmod +x /usr/local/bin/docker-entrypoint-wrapper.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint-wrapper.sh"]

#---------------------------------------
# Entrypoint
# Pi-hole already uses s6 overlay
# Running as root - Pi-hole handles user switching internally
#---------------------------------------
