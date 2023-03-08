# pihole-dot-doh-updatelists
Official pihole docker with DoT (DNS over TLS), DoH (DNS over HTTPS), and jacklul/pihole-updatelists. 

Multi-arch image built for both Raspberry Pi (arm64, arm32/v7, arm32/v6) and amd64.

## Usage:
For docker parameters, refer to [official pihole docker readme](https://github.com/pi-hole/pi-hole). Below is an docker compose example.

```
version: '3.0'

services:
  pihole:
    container_name: pihole
    image: mwatz/pihole-dot-doh-updatelists:latest
    hostname: pihole
    domainname: pihole.local
    ports:
      - "443:443/tcp"
      - "53:53/tcp"
      - "53:53/udp"
      #- "67:67/udp"
      - "80:80/tcp"
      - "853:853/tcp"
      - "853:853/udp"
    environment:
      - FTLCONF_LOCAL_IPV4=<IP address of device running the docker>
      - TZ=America/Los_Angeles
      - WEBPASSWORD=<Password to access pihole>
      - WEBTHEME=lcars
      - REV_SERVER=true
      - REV_SERVER_TARGET=<ip address of your router>
      - REV_SERVER_DOMAIN=localdomain
      - REV_SERVER_CIDR=<may be 192.168.1.0/24 if your router is 192.168.1.1>
      - PIHOLE_DNS_=127.1.1.1#5153;127.2.2.2#5253
      - DNSSEC="true"
    volumes:
      - './etc/pihole:/etc/pihole/:rw'
      - './etc/dnsmask:/etc/dnsmasq.d/:rw'
      - './etc/config:/config/:rw'
      - './etc/updatelists:/etc/pihole-updatelists/:rw'
    restart: unless-stopped
```
### Notes:
* Remember to set pihole env DNS1 and DNS2 to use the DoH / DoT IP below. If either DNS1 or DNS2 is NOT set, Pihole will use a non-encrypted service.
  * DoH service (cloudflared) runs at 127.1.1.1#5153. Uses cloudflare (1.1.1.1 / 1.0.0.1) by default
  * DoT service (stubby) runs at 127.2.2.2#5253. Uses google (8.8.8.8 / 8.8.4.4) by default
  * To use just DoH or just DoT service, set both DNS1 and DNS2 to the same value. 
* In addition to the 2 official paths, you can also map container /config to expose configuration yml files for cloudflared (cloudflared.yml) and stubby (stubby.yml).
  * Edit these files to add / remove services as you wish. The flexibility is yours.
* Credits:
  * Pihole base image is the official [pihole/pihole:latest](https://hub.docker.com/r/pihole/pihole/tags?page=1&name=latest)
  * doh and dot was based from https://github.com/testdasi/pihole-dot-doh
  * pihole-update lists is from https://github.com/jacklul/pihole-updatelists
  * Stubby is a standard debian package
  * Cloudflared client was obtained from [official site](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation#linux)
