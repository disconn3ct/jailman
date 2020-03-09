#!/usr/local/bin/bash
# This file contains the update script for nextcloud

echo "running nextcloud update"
iocage exec -f testnc su -m www -c "php /usr/local/www/nextcloud/updater/updater.phar  --no-interaction"
iocage exec testnc service caddy restart
