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
# Modify Pi-hole startup scripts
#---------------------------------------
# Inject our initialization into start.sh (runs before FTL starts)
RUN sed -i '/^\s*ftl_config/a\\n# Initialize dnsproxy and cache-domains configs\nif [ ! -f /config/dnsproxy.yml ] && [ -f /usr/local/share/dnsproxy-defaults/dnsproxy.yml ]; then\n    echo "  [i] Initializing /config/dnsproxy.yml from defaults"\n    cp /usr/local/share/dnsproxy-defaults/dnsproxy.yml /config/dnsproxy.yml\nfi\n\nif [ ! -f /etc/cache-domains/config/config.json ] && [ -f /usr/local/share/cache-domains-defaults/config.json ]; then\n    echo "  [i] Initializing /etc/cache-domains/config/config.json from defaults"\n    mkdir -p /etc/cache-domains/config\n    cp /usr/local/share/cache-domains-defaults/config.json /etc/cache-domains/config/config.json\nfi\n\n# Start DNSProxy (DoT/DoH) in background\necho "  [i] Starting DNSProxy on 127.0.0.1:5054"\n/usr/local/bin/dnsproxy --config-path=/config/dnsproxy.yml >/var/log/dnsproxy.log 2>&1 &' /usr/bin/start.sh

# Inject cache-domains initialization into bash_functions.sh (runs after gravity)
RUN sed -i '/^\s*pihole -g/a\\n# Initialize cache-domains after gravity\necho "  [i] Initializing cache-domains..."\nbash /usr/local/bin/_cachedomainsonboot.sh >/var/log/cache-domains-init.log 2>&1 &' /usr/bin/bash_functions.sh

# Add cache-domains cron job to crontab.txt
RUN if ! grep -q "lancache-dns-updates.sh" /crontab.txt 2>/dev/null; then \
    RANDOM_MINUTE=$((1 + RANDOM % 58)); \
    echo "${RANDOM_MINUTE} 4 * * * root PATH=\"/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin\" /usr/local/bin/lancache-dns-updates.sh >/var/log/lancache-dns-updates-cron.log 2>&1" >> /crontab.txt; \
    echo "Added cache-domains cron to /crontab.txt (04:${RANDOM_MINUTE})"; \
fi

#---------------------------------------
# Use Pi-hole's default entrypoint
#---------------------------------------
