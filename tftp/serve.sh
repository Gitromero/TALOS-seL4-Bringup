#!/bin/bash
#
# TFTP server for netbooting seL4 images from U-Boot on the Discovery Kit.
#
# Runs dnsmasq (TFTP only: no DNS, no DHCP) in Docker with host networking, so
# no sudo is needed (docker group is enough). Files are served from ./root.
#
# Usage: ./serve.sh [start|stop|status|logs]
#   IFACE=<interface> ./serve.sh start   # default: interface of the default route
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
NAME=sel4-tftp
IFACE="${IFACE:-$(ip route show default | awk '{print $5; exit}')}"

case "${1:-start}" in
start)
    if [ -z "$(docker images -q $NAME)" ]; then
        docker build -q -t $NAME "$HERE"
    fi
    chmod -R a+rX "$HERE/root"   # dnsmasq drops privileges to 'nobody'
    docker rm -f $NAME >/dev/null 2>&1 || true
    docker run -d --name $NAME --network host \
        -v "$HERE/root:/srv/tftp:ro" \
        $NAME --interface="$IFACE" --bind-interfaces >/dev/null
    ip=$(ip -4 -br addr show "$IFACE" | awk '{print $3}' | cut -d/ -f1)
    echo "TFTP serving $HERE/root on $IFACE ($ip)"
    echo "U-Boot:  dhcp; tftpboot 0x8e000000 $ip:<file>"
    ls -l "$HERE/root"
    ;;
stop)
    docker rm -f $NAME
    ;;
status)
    docker ps --filter name=$NAME --format '{{.Names}}: {{.Status}}'
    ;;
logs)
    docker logs -f $NAME
    ;;
*)
    echo "usage: $0 [start|stop|status|logs]" >&2
    exit 1
    ;;
esac
