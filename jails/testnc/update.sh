#!/usr/local/bin/bash
# This file contains the update script for nextcloud

echo "Updating nextcloud from CLI currently not supported, please use reinstall instead"
#TODO insert code to update nextcloud itself here
iocage exec testnc chown -R jackett:jackett /usr/local/share/Jackett /config
iocage exec testnc service caddy restart
