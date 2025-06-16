#!/bin/bash
# /etc/openvpn/client/dns-hooks.sh
# Resilient DNS hook for OpenVPN clients

LOG=/tmp/openvpn-dns.log
echo "$(date): DNS hook $script_type started" >> $LOG

if [ "$script_type" = "up" ]; then
    if [ -x /etc/openvpn/client/update-resolv-conf ]; then
        exec /etc/openvpn/client/update-resolv-conf "$@"
    elif [ -x /etc/openvpn/client/update-systemd-resolved ]; then
        exec /etc/openvpn/client/update-systemd-resolved "$@"
    else
        echo "$(date): No DNS updater found" >> $LOG
    fi
elif [ "$script_type" = "down" ]; then
    if [ -x /etc/openvpn/client/update-resolv-conf ]; then
        exec /etc/openvpn/client/update-resolv-conf "$@"
    elif [ -x /etc/openvpn/client/update-systemd-resolved ]; then
        exec /etc/openvpn/client/update-systemd-resolved "$@"
    else
        echo "$(date): No DNS cleanup found" >> $LOG
    fi
fi
