#!/usr/local/bin/bash
# This file contains the install script for qbittorrent + vpn
set -eao pipefail
# Ensure nothing happens before config
iocage exec qbitvpn service qbittorrent stop || true

# Check if dataset Downloads dataset exist, create if they do not.
createmount qbitvpn ${global_dataset_downloads}qbit /mnt/downloads

# Check if dataset Complete Downloads dataset exist, create if they do not.
createmount qbitvpn ${global_dataset_downloads}qbit/complete /mnt/downloads/complete

# Check if dataset InComplete Downloads dataset exist, create if they do not.
createmount qbitvpn ${global_dataset_downloads}qbit/incomplete /mnt/downloads/incomplete

# Copy ipfw rules to jail, replacing #TUNDEV# with tundev (default "tun0")
sed -e "s/#TUNDEV#/${qbitvpn_tundev:-tun0}/g" < ${SCRIPT_DIR}/jails/qbitvpn/includes/ipfw.rules > /mnt/${global_dataset_iocage}/jails/qbitvpn/root/etc/ipfw.rules
iocage exec qbitvpn chmod +x /etc/ipfw.rules
iocage exec qbitvpn sysrc "firewall_enable=YES"
iocage exec qbitvpn sysrc "firewall_script=/etc/ipfw.rules"

iocage exec qbitvpn chown -R qbittorrent: /config /mnt/downloads

iocage exec qbitvpn sysrc "qbittorrent_enable=YES"
iocage exec qbitvpn sysrc "qbittorrent_conf_dir=/config"
iocage exec qbitvpn sysrc "qbittorrent_download_dir=/mnt/downloads/complete"

iocage exec qbitvpn sysrc "openvpn_enable=YES"
iocage exec qbitvpn mkdir /usr/local/etc/openvpn
cp ${SCRIPT_DIR}/${qbitvpn_ovpnconf} /mnt/${global_dataset_iocage}/jails/qbitvpn/root/usr/local/etc/openvpn/

iocage exec qbitvpn service ipfw restart
iocage exec qbitvpn service openvpn restart

iocage exec qbitvpn sed -i '' -e 's_/config/qBittorrent/downloads/_/mnt/downloads/complete/_g' /config/qBittorrent/config/qBittorrent.conf
iocage exec qbitvpn service qbittorrent start
