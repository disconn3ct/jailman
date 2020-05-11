#!/usr/local/bin/bash
# This file contains the install script for transmission + vpn
set -eao pipefail

# Check if dataset Downloads dataset exist, create if they do not.
createmount transvpn "${global_dataset_downloads}trov" /mnt/downloads

# Check if dataset Complete Downloads dataset exist, create if they do not.
createmount transvpn "${global_dataset_downloads}trov/complete" /mnt/downloads/complete

# Check if dataset InComplete Downloads dataset exist, create if they do not.
createmount transvpn "${global_dataset_downloads}trov/incomplete" /mnt/downloads/incomplete

# Copy ipfw rules to jail, replacing #TUNDEV# with tundev (default "tun0")
sed -e "s/#TUNDEV#/${transvpn_tundev:-tun0}/g" < "${SCRIPT_DIR}/jails/transvpn/includes/ipfw.rules" > "/mnt/${global_dataset_iocage}/jails/transvpn/root/etc/ipfw.rules"

iocage exec transvpn chown -R transmission:transmission /config
iocage exec transvpn sysrc "transmission_enable=YES"
iocage exec transvpn sysrc "transmission_conf_dir=/config"
iocage exec transvpn sysrc "transmission_download_dir=/mnt/downloads/complete"

iocage exec transvpn sysrc "openvpn_enable=YES"
iocage exec transvpn mkdir /usr/local/etc/openvpn
cp "${SCRIPT_DIR}/${transvpn_ovpnconf}" "/mnt/${global_dataset_iocage}/jails/transvpn/root/usr/local/etc/openvpn/"
iocage exec transvpn sysrc "firewall_enable=YES"
iocage exec transvpn sysrc "firewall_script=/etc/ipfw.rules"
iocage exec transvpn sed -i '' -e 's/\([[:space:]]*"rpc-whitelist-enabled":[[:space:]]*\)true,/\1false,/' /etc/ipfw.rules

iocage exec transvpn service ipfw restart
iocage exec transvpn service openvpn restart

echo "Disabling RPC whitelist, you may want to reenable it with the specific IP's you will access transmission with by editing /config/settings.json"
iocage exec transvpn service transmission stop
iocage exec transvpn sed -i '' -e 's/\([[:space:]]*"rpc-whitelist-enabled":[[:space:]]*\)true,/\1false,/' /config/settings.json

iocage exec transvpn service transmission start