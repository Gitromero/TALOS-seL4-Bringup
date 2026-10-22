# TFTP-only dnsmasq (DNS and DHCP off) for netbooting seL4 images from U-Boot.
# Do not add --tftp-single-port: with it, dnsmasq in this container received the
# board's requests but failed every reply with "Network is unreachable".
# Normal TFTP passes a host firewall that only allows inbound UDP 69, because
# each transfer's later packets are replies to a flow the server opened.
FROM debian:bookworm
RUN apt-get update && apt-get install -y --no-install-recommends dnsmasq && rm -rf /var/lib/apt/lists/*
ENTRYPOINT ["dnsmasq", "--keep-in-foreground", "--log-facility=-", "--port=0", "--enable-tftp", "--tftp-root=/srv/tftp", "--log-queries"]
