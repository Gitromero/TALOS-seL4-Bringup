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
    ls -l "$HERE/root"
    # Ready-to-paste U-Boot commands, one block per image, with this host's IP.
    for f in "$HERE"/root/*; do
        [ -f "$f" ] || continue
        echo
        echo "At RISC-V #, to boot $(basename "$f") (paste one line at a time):"
        echo "  setenv autoload no"
        echo "  dhcp"
        echo "  tftpboot 0x8e000000 $ip:$(basename "$f")"
        echo "  iminfo 0x8e000000"
        echo "  bootm 0x8e000000 - \${fdtcontroladdr}"
    done
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
