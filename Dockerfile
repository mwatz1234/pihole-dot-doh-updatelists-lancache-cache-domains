#---------------------------------------
# Base image
#---------------------------------------
ARG FRM='pihole/pihole:latest'
ARG TAG='latest'
ARG TARGETPLATFORM
FROM ${FRM}

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
        php-cli \
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
RUN /bin/bash /temp/install.sh \
    && rm -rf /temp

#---------------------------------------
# Pi-hole updatelists (optional)
#---------------------------------------
RUN wget -O - https://raw.githubusercontent.com/jacklul/pihole-updatelists/master/install.sh | bash /dev/stdin docker

#---------------------------------------
# Build info
#---------------------------------------
RUN echo "$(date "+%d.%m.%Y %T") Built from ${FRM} with tag ${TAG}" >> /build_date.info

#---------------------------------------
# Entrypoint
# Pi-hole already uses s6 overlay
#---------------------------------------
USER pihole
