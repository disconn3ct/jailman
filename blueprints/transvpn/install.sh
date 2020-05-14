#!/usr/local/bin/bash
# This file contains the install script for transmission + openvpn
set -eao pipefail

dlprefixtmp="${1}_download_prefix"
dlprefix="${!dlprefixtmp:-}"

tundevtmp="${1}_tundev"
tundev="${!tundevtmp:-tun0}"

ovpntmp="${1}_ovpnconf"
ovpnconf="${!ovpntmp:?}"

# Check if dataset Downloads dataset exist, create if they do not.
createdownload "${1}" "/mnt/downloads" "${dlprefix}"

# Copy ipfw rules to jail, replacing #TUNDEV# with tundev (default "tun0")
sed -e "s/#TUNDEV#/${tundev}/g" < "${SCRIPT_DIR:?}/blueprints/transvpn/includes/ipfw.rules" > "/mnt/${global_dataset_iocage:?}/jails/${1}/root/etc/ipfw.rules"

iocage exec "${1}" chown -R transmission:transmission /config
iocage exec "${1}" sysrc "transmission_enable=YES"
iocage exec "${1}" sysrc "transmission_conf_dir=/config"
iocage exec "${1}" sysrc "transmission_download_dir=/mnt/downloads/complete"

iocage exec "${1}" sysrc "openvpn_enable=YES"
iocage exec "${1}" mkdir /usr/local/etc/openvpn
cp "${SCRIPT_DIR}/${ovpnconf:?}" "/mnt/${global_dataset_iocage}/jails/${1}/root/usr/local/etc/openvpn/"
iocage exec "${1}" sysrc "firewall_enable=YES"
iocage exec "${1}" sysrc "firewall_script=/etc/ipfw.rules"
iocage exec "${1}" sed -i '' -e 's/\([[:space:]]*"rpc-whitelist-enabled":[[:space:]]*\)true,/\1false,/' /etc/ipfw.rules

iocage exec "${1}" service ipfw restart
iocage exec "${1}" service openvpn restart

echo "Disabling RPC whitelist, you may want to reenable it with the specific IP's you will access transmission with by editing /config/settings.json"
iocage exec "${1}" service transmission stop
iocage exec "${1}" sed -i '' -e 's/\([[:space:]]*"rpc-whitelist-enabled":[[:space:]]*\)true,/\1false,/' /config/settings.json
iocage exec "${1}" service transmission start
