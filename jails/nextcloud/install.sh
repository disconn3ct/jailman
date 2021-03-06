#!/usr/local/bin/bash
# This script installs the current release of Nextcloud into a create jail
# Based on the example by danb35: https://github.com/danb35/freenas-iocage-nextcloud


# Initialise defaults
JAIL_NAME="nextcloud"
JAIL_IP="$(sed 's|\(.*\)/.*|\1|' <<<"${nextcloud_ip4_addr}" )"
DATABASE="$nextcloud_database"
INCLUDES_PATH="${SCRIPT_DIR}/jails/nextcloud/includes"
STANDALONE_CERT=${nextcloud_standalone_cert}
SELFSIGNED_CERT=${nextcloud_selfsigned_cert}
DNS_CERT=${nextcloud_dns_cert}
NO_CERT=${nextcloud_no_cert}
DL_FLAGS=${nextcloud_dl_flags}
DNS_SETTING=${nextcloud_dns_settings}
CERT_EMAIL=${nextcloud_cert_email}
HOST_NAME=${nextcloud_host_name}

# Only generate new DB passwords when using buildin database
# Set DB username and database to fixed "nextcloud"

if [ "${DATABASE}" = "pgsql-external" ]; then
  DB_NAME="PostgreSQL"
  DB_HOST="${nextcloud_db_host}"
  DB_DATABASE="${nextcloud_db_database}"
  DB_USER="${nextcloud_db_user}"
  DB_PASSWORD="${nextcloud_db_password}"
elif [ "${DATABASE}" = "mariadb-external" ]; then
  DB_NAME="MariaDB"
  DB_HOST="${nextcloud_db_host}"
  DB_DATABASE="${nextcloud_db_database}"
  DB_USER="${nextcloud_db_user}"
  DB_PASSWORD="${nextcloud_db_password}"
elif [ "${DATABASE}" = "mariadb-jail" ]; then
  DB_DATABASE="nextcloud"
  DB_USER="nextcloud"
  DB_HOST="$(sed 's|\(.*\)/.*|\1|' <<<"${mariadb_ip4_addr}"):3306"
  DB_PASSWORD="${nextcloud_db_password}"
else
  echo "Invalid ${JAIL_NAME}_database selected please select one from the following options:"
  echo "mariadb-jail, mariadb-external, pgsql-external"
  exit 1
fi


ADMIN_PASSWORD=$(openssl rand -base64 12)

#####
# 
# Input Sanity Check 
#
#####


# Check that necessary variables were set by nextcloud-config
if [ -z "${nextcloud_ip4_addr}" ]; then
  echo 'Configuration error: The Nextcloud jail does NOT accept DHCP'
  echo 'Please reinstall using a fixed IP adress'
  exit 1
fi

if [ -z "${DB_PASSWORD}" ]; then
  echo 'Configuration error: The Nextcloud Jail needs a database password'
  echo 'Please reinstall with a defifined: db_password'
  exit 1
fi

if [ -z "${DB_USER}" ]; then
  echo 'Configuration error: The Nextcloud Jail needs a database user'
  echo 'Please reinstall with a defifined: db_user'
  exit 1
fi

if [ -z "${DB_HOST}" ]; then
	echo 'Configuration error: The Nextcloud Jail needs a database host'
  echo 'Please reinstall with a defifined: db_host'
  exit 1
fi

if [ -z "${DB_DATABASE}" ]; then
	echo 'Configuration error: The Nextcloud Jail needs a database name'
  echo 'Please reinstall with a defifined: db_database'
  exit 1
fi

if [ -z "${nextcloud_time_zone}" ]; then
  echo 'Configuration error: TIME_ZONE must be set'
  exit 1
fi
if [ -z "${HOST_NAME}" ]; then
  echo 'Configuration error: HOST_NAME must be set'
  exit 1
fi
if [ $STANDALONE_CERT -eq 0 ] && [ $DNS_CERT -eq 0 ] && [ $NO_CERT -eq 0 ] && [ $SELFSIGNED_CERT -eq 0 ]; then
  echo 'Configuration error: Either STANDALONE_CERT, DNS_CERT, NO_CERT,'
  echo 'or SELFSIGNED_CERT must be set to 1.'
  exit 1
fi
if [ $STANDALONE_CERT -eq 1 ] && [ $DNS_CERT -eq 1 ] ; then
  echo 'Configuration error: Only one of STANDALONE_CERT and DNS_CERT'
  echo 'may be set to 1.'
  exit 1
fi

if [ $DNS_CERT -eq 1 ] && [ -z "${DNS_PLUGIN}" ] ; then
  echo "DNS_PLUGIN must be set to a supported DNS provider."
  echo "See https://caddyserver.com/docs under the heading of \"DNS Providers\" for list."
  echo "Be sure to omit the prefix of \"tls.dns.\"."
  exit 1
fi  
if [ $DNS_CERT -eq 1 ] && [ -z "${DNS_ENV}" ] ; then
  echo "DNS_ENV must be set to a your DNS provider\'s authentication credentials."
  echo "See https://caddyserver.com/docs under the heading of \"DNS Providers\" for more."
  exit 1
fi  

if [ $DNS_CERT -eq 1 ] ; then
  DL_FLAGS="tls.dns.${DNS_PLUGIN}"
  DNS_SETTING="dns ${DNS_PLUGIN}"
fi

# Make sure DB_PATH is empty -- if not, MariaDB/PostgreSQL will choke
if [ "$(ls -A "/mnt/${global_dataset_config}/${JAIL_NAME}/config")" ]; then
	echo "Reinstall of Nextcloud detected... "
	echo "External database selected, unable to verify compatibility. REINSTALL MIGHT NOT WORK... Continuing"
	REINSTALL="true"
fi


#####
	# 
# Fstab And Mounts
#
#####

# Create and Mount portsnap
createmount ${JAIL_NAME} ${global_dataset_config}/portsnap
createmount ${JAIL_NAME} ${global_dataset_config}/portsnap/db /var/db/portsnap
createmount ${JAIL_NAME} ${global_dataset_config}/portsnap/ports /usr/ports

# Create and Mount Nextcloud, Config and Files
createmount ${JAIL_NAME} ${global_dataset_config}/${JAIL_NAME}/config /usr/local/www/nextcloud/config
createmount ${JAIL_NAME} ${global_dataset_config}/${JAIL_NAME}/themes /usr/local/www/nextcloud/themes
createmount ${JAIL_NAME} ${global_dataset_config}/${JAIL_NAME}/files /config/files

# Install includes fstab
iocage exec "${JAIL_NAME}" mkdir -p /mnt/includes
iocage fstab -a "${JAIL_NAME}" "${INCLUDES_PATH}" /mnt/includes nullfs rw 0 0


iocage exec "${JAIL_NAME}" chown -R www:www /config/files
iocage exec "${JAIL_NAME}" chmod -R 770 /config/files


#####
# 
# Basic dependency install
#
#####

iocage exec "${JAIL_NAME}" "if [ -z /usr/ports ]; then portsnap fetch extract; else portsnap auto; fi"

if [ "${DATABASE}" = "mariadb-external" ] || [ "${DATABASE}" = "mariadb-jail" ]; then
  iocage exec "${JAIL_NAME}" pkg install -qy mariadb103-client php73-pdo_mysql php73-mysqli
elif [ "${DATABASE}" = "pgsql-external" ]; then
  iocage exec "${JAIL_NAME}" pkg install -qy postgresql10-client php73-pgsql php73-pdo_pgsql
fi

fetch -o /tmp https://getcaddy.com
if ! iocage exec "${JAIL_NAME}" bash -s personal "${DL_FLAGS}" < /tmp/getcaddy.com
then
	echo "Failed to download/install Caddy"
	exit 1
fi

iocage exec "${JAIL_NAME}" sysrc redis_enable="YES"
iocage exec "${JAIL_NAME}" sysrc php_fpm_enable="YES"
iocage exec "${JAIL_NAME}" sh -c "make -C /usr/ports/www/php73-opcache clean install BATCH=yes"
iocage exec "${JAIL_NAME}" sh -c "make -C /usr/ports/devel/php73-pcntl clean install BATCH=yes"


#####
# 
# Install Nextcloud
#
#####

FILE="latest-18.tar.bz2"
if ! iocage exec "${JAIL_NAME}" fetch -o /tmp https://download.nextcloud.com/server/releases/"${FILE}" https://download.nextcloud.com/server/releases/"${FILE}".asc https://nextcloud.com/nextcloud.asc
then
	echo "Failed to download Nextcloud"
	exit 1
fi
iocage exec "${JAIL_NAME}" gpg --import /tmp/nextcloud.asc
if ! iocage exec "${JAIL_NAME}" gpg --verify /tmp/"${FILE}".asc
then
	echo "GPG Signature Verification Failed!"
	echo "The Nextcloud download is corrupt."
	exit 1
fi
iocage exec "${JAIL_NAME}" tar xjf /tmp/"${FILE}" -C /usr/local/www/
iocage exec "${JAIL_NAME}" chown -R www:www /usr/local/www/nextcloud/


# Generate and install self-signed cert, if necessary
if [ $SELFSIGNED_CERT -eq 1 ] && [ ! -f "/mnt/${global_dataset_config}/${JAIL_NAME}/ssl/privkey.pem" ]; then
	echo "No ssl certificate present, generating self signed certificate"
	if [ ! -d "/mnt/${global_dataset_config}/${JAIL_NAME}/ssl" ]; then
		echo "cert folder not existing... creating..."
		iocage exec ${JAIL_NAME} mkdir /config/ssl
	fi
	openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 -subj "/C=US/ST=Denial/L=Springfield/O=Dis/CN=${HOST_NAME}" -keyout "${INCLUDES_PATH}"/privkey.pem -out "${INCLUDES_PATH}"/fullchain.pem
	iocage exec "${JAIL_NAME}" cp /mnt/includes/privkey.pem /config/ssl/privkey.pem
	iocage exec "${JAIL_NAME}" cp /mnt/includes/fullchain.pem /config/ssl/fullchain.pem
fi

# Copy and edit pre-written config files
iocage exec "${JAIL_NAME}" cp -f /mnt/includes/php.ini /usr/local/etc/php.ini
iocage exec "${JAIL_NAME}" cp -f /mnt/includes/redis.conf /usr/local/etc/redis.conf
iocage exec "${JAIL_NAME}" cp -f /mnt/includes/www.conf /usr/local/etc/php-fpm.d/
if [ $STANDALONE_CERT -eq 1 ] || [ $DNS_CERT -eq 1 ]; then
  iocage exec "${JAIL_NAME}" cp -f /mnt/includes/remove-staging.sh /root/
fi
if [ $NO_CERT -eq 1 ]; then
  echo "Copying Caddyfile for no SSL"
  iocage exec "${JAIL_NAME}" cp -f /mnt/includes/Caddyfile-nossl /usr/local/www/Caddyfile
elif [ $SELFSIGNED_CERT -eq 1 ]; then
  echo "Copying Caddyfile for self-signed cert"
  iocage exec "${JAIL_NAME}" cp -f /mnt/includes/Caddyfile-selfsigned /usr/local/www/Caddyfile
else
  echo "Copying Caddyfile for Let's Encrypt cert"
  iocage exec "${JAIL_NAME}" cp -f /mnt/includes/Caddyfile /usr/local/www/
fi
iocage exec "${JAIL_NAME}" cp -f /mnt/includes/caddy /usr/local/etc/rc.d/


iocage exec "${JAIL_NAME}" sed -i '' "s/yourhostnamehere/${HOST_NAME}/" /usr/local/www/Caddyfile
iocage exec "${JAIL_NAME}" sed -i '' "s/DNS-PLACEHOLDER/${DNS_SETTING}/" /usr/local/www/Caddyfile
iocage exec "${JAIL_NAME}" sed -i '' "s/JAIL-IP/${JAIL_IP}/" /usr/local/www/Caddyfile
iocage exec "${JAIL_NAME}" sed -i '' "s|mytimezone|${nextcloud_time_zone}|" /usr/local/etc/php.ini

iocage exec "${JAIL_NAME}" sysrc caddy_enable="YES"
iocage exec "${JAIL_NAME}" sysrc caddy_cert_email="${CERT_EMAIL}"
iocage exec "${JAIL_NAME}" sysrc caddy_SNI_default="${HOST_NAME}"
iocage exec "${JAIL_NAME}" sysrc caddy_env="${DNS_ENV}"

iocage restart "${JAIL_NAME}"

if [ "${REINSTALL}" == "true" ]; then
	echo "Reinstall detected, skipping generaion of new config and database"
else
	
	# Secure database, set root password, create Nextcloud DB, user, and password
	if  [ "${DATABASE}" = "mariadb-jail" ]; then
		iocage exec "mariadb" mysql -u root -e "CREATE DATABASE ${DB_DATABASE};"
		iocage exec "mariadb" mysql -u root -e "GRANT ALL ON ${DB_DATABASE}.* TO ${DB_USER}@${JAIL_IP} IDENTIFIED BY '${DB_PASSWORD}';"
		iocage exec "mariadb" mysqladmin reload
	fi
	
	
	# Save passwords for later reference
	iocage exec "${JAIL_NAME}" echo "${DB_NAME} root password is ${DB_ROOT_PASSWORD}" > /root/${JAIL_NAME}_db_password.txt
	iocage exec "${JAIL_NAME}" echo "Nextcloud database password is ${DB_PASSWORD}" >> /root/${JAIL_NAME}_db_password.txt
	iocage exec "${JAIL_NAME}" echo "Nextcloud Administrator password is ${ADMIN_PASSWORD}" >> /root/${JAIL_NAME}_db_password.txt
	
	# CLI installation and configuration of Nextcloud
	if [ "${DATABASE}" = "mariadb-external" ] || [ "${DATABASE}" = "mariadb-jail" ]; then
		iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ maintenance:install --database=\"mysql\" --database-name=\"${DB_DATABASE}\" --database-user=\"${DB_USER}\" --database-pass=\"${DB_PASSWORD}\" --database-host=\"${DB_HOST}\" --admin-user=\"admin\" --admin-pass=\"${ADMIN_PASSWORD}\" --data-dir=\"/config/files\""
		iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set mysql.utf8mb4 --type boolean --value=\"true\""
	elif [ "${DATABASE}" = "pgsql-external" ]; then
		iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ maintenance:install --database=\"pgsql\" --database-name=\"${DB_DATABASE}\" --database-user=\"${DB_USER}\" --database-pass=\"${DB_PASSWORD}\" --database-host=\"${DB_HOST}\" --admin-user=\"admin\" --admin-pass=\"${ADMIN_PASSWORD}\" --data-dir=\"/config/files\""
	fi
	iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ db:add-missing-indices"
	iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ db:convert-filecache-bigint --no-interaction"
	iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set logtimezone --value=\"${nextcloud_time_zone}\""
	iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set log_type --value="file"'
	iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set logfile --value="/var/log/nextcloud.log"'
	iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set loglevel --value="2"'
	iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set logrotate_size --value="104847600"'
	iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set memcache.local --value="\OC\Memcache\APCu"'
	iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set redis host --value="/tmp/redis.sock"'
	iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set redis port --value=0 --type=integer'
	iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set memcache.locking --value="\OC\Memcache\Redis"'
	if [ $NO_CERT -eq 1 ]; then
		iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set overwrite.cli.url --value=\"http://${HOST_NAME}/\""
	else
		iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set overwrite.cli.url --value=\"https://${HOST_NAME}/\""
	fi
	iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set htaccess.RewriteBase --value="/"'
	iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ maintenance:update:htaccess'
	iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set trusted_domains 1 --value=\"${HOST_NAME}\""
	iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set trusted_domains 2 --value=\"${JAIL_IP}\""
	iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ app:enable encryption'
	iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ encryption:enable'
	iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ encryption:disable'
	iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ background:cron'
	
fi

iocage exec "${JAIL_NAME}" touch /var/log/nextcloud.log
iocage exec "${JAIL_NAME}" chown www /var/log/nextcloud.log
iocage exec "${JAIL_NAME}" su -m www -c 'php -f /usr/local/www/nextcloud/cron.php'
iocage exec "${JAIL_NAME}" crontab -u www /mnt/includes/www-crontab

# Don't need /mnt/includes any more, so unmount it
iocage fstab -r "${JAIL_NAME}" "${INCLUDES_PATH}" /mnt/includes nullfs rw 0 0

# Done!
echo "Installation complete!"
if [ $NO_CERT -eq 1 ]; then
  echo "Using your web browser, go to http://${HOST_NAME} to log in"
else
  echo "Using your web browser, go to https://${HOST_NAME} to log in"
fi

if [ "${REINSTALL}" == "true" ]; then
	echo "You did a reinstall, please use your old database and account credentials"
else

	echo "Default user is admin, password is ${ADMIN_PASSWORD}"
	echo ""

	echo "Database Information"
	echo "--------------------"
	echo "Database user = ${DB_USER}"
	echo "Database password = ${DB_PASSWORD}"
	echo ""
	echo "All passwords are saved in /root/${JAIL_NAME}_db_password.txt"
fi

echo ""
if [ $STANDALONE_CERT -eq 1 ] || [ $DNS_CERT -eq 1 ]; then
  echo "You have obtained your Let's Encrypt certificate using the staging server."
  echo "This certificate will not be trusted by your browser and will cause SSL errors"
  echo "when you connect.  Once you've verified that everything else is working"
  echo "correctly, you should issue a trusted certificate.  To do this, run:"
  echo "  iocage exec ${JAIL_NAME} /root/remove-staging.sh"
  echo ""
elif [ $SELFSIGNED_CERT -eq 1 ]; then
  echo "You have chosen to create a self-signed TLS certificate for your Nextcloud"
  echo "installation.  This certificate will not be trusted by your browser and"
  echo "will cause SSL errors when you connect.  If you wish to replace this certificate"
  echo "with one obtained elsewhere, the private key is located at:"
  echo "/config/ssl/privkey.pem"
  echo "The full chain (server + intermediate certificates together) is at:"
  echo "/config/ssl/fullchain.pem"
  echo ""
fi

