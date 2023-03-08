#!/bin/bash

# install basic packages
#apt-get -y update \
#    && apt-get -y dist-upgrade \
#    && apt-get -y install sudo bash nano curl wget php-cli php-sqlite3 php-intl php-curl
    
# install stubby
#apt-get -Vy install stubby

# clean stubby config
mkdir -p /etc/stubby \
    && rm -f /etc/stubby/stubby.yml

DETECTED_ARCH=$(dpkg --print-architecture)

# install cloudflared
mkdir -p /tmp \
    && cd /tmp
if [[ ${TARGETPLATFORM} =~ "arm64" ]]
then
    curl -sL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb -o /tmp/cloudflared.deb
    dpkg --add-architecture arm64
    echo "$(date "+%d.%m.%Y %T") Added cloudflared for ${TARGETPLATFORM}" >> /build.info
elif [[ ${TARGETPLATFORM} =~ "amd64" ]]
then 
    curl -sL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o /tmp/cloudflared.deb
    dpkg --add-architecture amd64
    echo "$(date "+%d.%m.%Y %T") Added cloudflared for ${TARGETPLATFORM}" >> /build.info
elif [[ ${TARGETPLATFORM} =~ "386" ]]
then
    curl -sL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-386.deb -o /tmp/cloudflared.deb
    dpkg --add-architecture 386
    echo "$(date "+%d.%m.%Y %T") Added cloudflared for ${TARGETPLATFORM}" >> /build.info
elif [[ ${TARGETPLATFORM} =~ 'arm/v7' ]]
then
    curl -sL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm.deb -o /tmp/cloudflared.deb
    dpkg --add-architecture arm
    echo "$(date "+%d.%m.%Y %T") Added cloudflared for ${TARGETPLATFORM}" >> /build.info
elif [[ ${TARGETPLATFORM} =~ 'arm/v6' ]]
then
    #curl -sL https://hobin.ca/cloudflared/latest?type=deb -o /tmp/cloudflared.deb
    wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm
else 
    echo "$(date "+%d.%m.%Y %T") Unsupported platform - cloudflared not added" >> /build.info
fi
  if [[ ${TARGETPLATFORM} =~ 'arm/v6' ]]
  then
    sudo cp ./cloudflared-linux-arm /usr/local/bin/cloudflared
    sudo chmod +x /usr/local/bin/cloudflared
    cloudflared -v    
  else
    apt install /tmp/cloudflared.deb \
        && rm -f /tmp/cloudflared.deb \
        && useradd -s /usr/sbin/nologin -r -M cloudflared \
        && chown cloudflared:cloudflared /usr/local/bin/cloudflared
  fi

# clean cloudflared config
mkdir -p /etc/cloudflared \
    && rm -f /etc/cloudflared/config.yml

# clean up
apt-get -y autoremove \
    && apt-get -y autoclean \
    && apt-get -y clean \
    && rm -fr /tmp/* /var/tmp/* /var/lib/apt/lists/*

# Creating pihole-dot-doh service
mkdir -p /etc/services.d/pihole-dot-doh

# run file
echo '#!/bin/bash' > /etc/services.d/pihole-dot-doh/run
# Copy config file if not exists
echo 'cp -n /temp/stubby.yml /config/' >> /etc/services.d/pihole-dot-doh/run
echo 'cp -n /temp/cloudflared.yml /config/' >> /etc/services.d/pihole-dot-doh/run
# run stubby in background
echo 's6-echo "Starting stubby"' >> /etc/services.d/pihole-dot-doh/run
echo 'stubby -g -C /config/stubby.yml' >> /etc/services.d/pihole-dot-doh/run
# run cloudflared in foreground
echo 's6-echo "Starting cloudflared"' >> /etc/services.d/pihole-dot-doh/run
echo '/usr/local/bin/cloudflared --config /config/cloudflared.yml' >> /etc/services.d/pihole-dot-doh/run

# finish file
echo '#!/bin/bash' > /etc/services.d/pihole-dot-doh/finish
echo 's6-echo "Stopping stubby"' >> /etc/services.d/pihole-dot-doh/finish
echo 'killall -9 stubby' >> /etc/services.d/pihole-dot-doh/finish
echo 's6-echo "Stopping cloudflared"' >> /etc/services.d/pihole-dot-doh/finish
echo 'killall -9 cloudflared' >> /etc/services.d/pihole-dot-doh/finish

# Make bash scripts executable
chmod -v +x /etc/services.d/pihole-dot-doh/run
chmod -v +x /etc/services.d/pihole-dot-doh/finish
