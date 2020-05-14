#!/usr/local/bin/bash
# This file contains the install script for qbittorrent + openvpn
set -eao pipefail

dlprefixtmp="${1}_download_prefix"
dlprefix="${!dlprefixtmp:-}"

tundevtmp="${1}_tundev"
tundev="${!tundevtmp:-tun0}"

ovpntmp="${1}_ovpnconf"
ovpnconf="${!ovpntmp:?}"

# Ensure nothing happens before config
iocage exec "${1}" service qbittorrent stop || true

# Check if dataset Downloads dataset exist, create if they do not.
createdownload "${1}" "/mnt/downloads" "${dlprefix}"

# Copy ipfw rules to jail, replacing #TUNDEV# with tundev (default "tun0")
sed -e "s/#TUNDEV#/${tundev}/g" < "${SCRIPT_DIR:?}/blueprints/qbitvpn/includes/ipfw.rules" > "/mnt/${global_dataset_iocage:?}/jails/${1}/root/etc/ipfw.rules"

iocage exec "${1}" chown -R qbittorrent: /config /mnt/downloads
iocage exec "${1}" sysrc "qbittorrent_enable=YES"
iocage exec "${1}" sysrc "qbittorrent_conf_dir=/config"
iocage exec "${1}" sysrc "qbittorrent_download_dir=/mnt/downloads/complete"

iocage exec "${1}" sysrc "openvpn_enable=YES"
iocage exec "${1}" mkdir /usr/local/etc/openvpn
cp "${SCRIPT_DIR}/${ovpnconf:?}" "/mnt/${global_dataset_iocage}/jails/${1}/root/usr/local/etc/openvpn/"
iocage exec "${1}" sysrc "firewall_enable=YES"
iocage exec "${1}" sysrc "firewall_script=/etc/ipfw.rules"
iocage exec "${1}" sed -i '' -e 's/\([[:space:]]*"rpc-whitelist-enabled":[[:space:]]*\)true,/\1false,/' /etc/ipfw.rules

iocage exec "${1}" service ipfw restart
iocage exec "${1}" service openvpn restart

iocage exec "${1}" sed -i '' -e 's_/config/qBittorrent/downloads/_/mnt/downloads/complete/_g' /config/qBittorrent/config/qBittorrent.conf
iocage exec "${1}" service qbittorrent start
