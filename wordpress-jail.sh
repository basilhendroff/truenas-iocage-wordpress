#!/bin/sh
# Build an iocage jail under FreeNAS 11.3-12.0 using the current release of WordPress 5.5
# git clone https://github.com/basilhendroff/freenas-iocage-wordpress

GREEN="\e[1;32m"
NOCOLOUR="\e[0m"

# Check for root privileges
if ! [ $(id -u) = 0 ]; then
   echo "This script must be run with root privileges" 
   exit 1
fi

#####
#
echo -e "${GREEN}General configuration...${NOCOLOUR}"
#
#####

# Initialize defaults
JAIL_IP=""
JAIL_INTERFACES=""
DEFAULT_GW_IP=""
INTERFACE="vnet0"
VNET="on"
POOL_PATH=""
JAIL_NAME="wordpress"
TIME_ZONE=""
HOST_NAME=""
DB_PATH=""
WP_PATH=""
CONFIG_NAME="wordpress-config"

# Check for wordpress-config and set configuration
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "${SCRIPT}")
if ! [ -e "${SCRIPTPATH}"/"${CONFIG_NAME}" ]; then
  echo "${SCRIPTPATH}/${CONFIG_NAME} must exist."
  exit 1
fi
. "${SCRIPTPATH}"/"${CONFIG_NAME}"
INCLUDES_PATH="${SCRIPTPATH}"/includes

RELEASE=$(freebsd-version | sed "s/STABLE/RELEASE/g" | sed "s/-p[0-9]*//")
JAILS_MOUNT=$(zfs get -H -o value mountpoint $(iocage get -p)/iocage)

#####
#
echo -e "${GREEN}Input/Config Sanity checks...${NOCOLOUR}"
#
#####

# Check that necessary variables were set by nextcloud-config
if [ -z "${JAIL_IP}" ]; then
  echo 'Configuration error: JAIL_IP must be set'
  exit 1
fi
if [ -z "${JAIL_INTERFACES}" ]; then
  echo 'JAIL_INTERFACES defaulting to: vnet0:bridge0'
  JAIL_INTERFACES="vnet0:bridge0"
fi
if [ -z "${DEFAULT_GW_IP}" ]; then
  echo 'Configuration error: DEFAULT_GW_IP must be set'
  exit 1
fi
if [ -z "${POOL_PATH}" ]; then
  POOL_PATH="/mnt/$(iocage get -p)"
  echo 'POOL_PATH defaulting to '$POOL_PATH
fi
#if [ -z "${TIME_ZONE}" ]; then
#  echo 'Configuration error: TIME_ZONE must be set'
#  exit 1
#fi
#if [ -z "${HOST_NAME}" ]; then
#  echo 'Configuration error: HOST_NAME must be set'
#  exit 1
#fi

# If DB_PATH and WP_PATH weren't set in wordpress-config, set them
if [ -z "${DB_PATH}" ]; then
  DB_PATH="${POOL_PATH}"/apps/wordpress/db
fi
if [ -z "${WP_PATH}" ]; then
  WP_PATH="${POOL_PATH}"/apps/wordpress/wp
fi

# Sanity check DB_PATH and WP_PATH -- they have to be different and can't be the same as POOL_PATH
if [ "${WP_PATH}" = "${DB_PATH}" ]
then
  echo "WP_PATH and DB_PATH must be different!"
  exit 1
fi
if [ "${DB_PATH}" = "${POOL_PATH}" ] || [ "${WP_PATH}" = "${POOL_PATH}" ]
then
  echo "DB_PATH and WP_PATH must all be different from POOL_PATH!"
  exit 1
fi

# Extract IP and netmask, sanity check netmask
IP=$(echo ${JAIL_IP} | cut -f1 -d/)
NETMASK=$(echo ${JAIL_IP} | cut -f2 -d/)
if [ "${NETMASK}" = "${IP}" ]
then
  NETMASK="24"
fi
if [ "${NETMASK}" -lt 8 ] || [ "${NETMASK}" -gt 30 ]
then
  NETMASK="24"
fi

# Check for reinstall
#if [ "$(ls -A "${CONFIG_PATH}")" ]; then
#	echo "Existing Nextcloud config detected... Checking Database compatibility for reinstall"
#	if [ "$(ls -A "${DB_PATH}/${DATABASE}")" ]; then
#		echo "Database is compatible, continuing..."
#		REINSTALL="true"
#	else
#		echo "ERROR: You can not reinstall without the previous database"
#		echo "Please try again after removing your config files or using the same database used previously"
#		exit 1
#	fi
#fi

#####
#
echo -e "${GREEN}Jail Creation...`date`${NOCOLOUR}"
echo -e "${GREEN}Time for a cuppa. Installing packages will take a while.${NOCOLOUR}"
#
#####

# List packages to be auto-installed after jail creation
# See https://make.wordpress.org/hosting/handbook/handbook/server-environment/

cat <<__EOF__ >/tmp/pkg.json
	{
  "pkgs":[
  "php74","php74-curl","php74-dom","php74-exif","php74-fileinfo","php74-json","php74-mbstring",
  "php74-mysqli","php74-pecl-libsodium","php74-openssl","php74-pecl-imagick","php74-xml","php74-zip",
  "php74-filter","php74-gd","php74-iconv","php74-pecl-mcrypt","php74-simplexml","php74-xmlreader","php74-zlib",
  "php74-ftp","php74-pecl-ssh2","php74-sockets","mariadb104-server","php74-pdo_mysql"
  ]
}
__EOF__

# Create the jail and install previously listed packages
if ! iocage create --name "${JAIL_NAME}" -p /tmp/pkg.json -r "${RELEASE}" interfaces="${JAIL_INTERFACES}" ip4_addr="${INTERFACE}|${IP}/${NETMASK}" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}" vnet="${VNET}"
then
	echo "Failed to create jail"
	exit 1
fi
rm /tmp/pkg.json

#####
#
echo -e "${GREEN}Directory Creation and Mounting...`date`${NOCOLOUR}"
#
#####

mkdir -p "${DB_PATH}"
chown -R 88:88 "${DB_PATH}"
iocage fstab -a "${JAIL_NAME}" "${DB_PATH}"  /var/db/mysql  nullfs  rw  0  0

mkdir -p "${WP_PATH}"
chown -R 80:80 "${WP_PATH}"
iocage exec "${JAIL_NAME}" mkdir -p /usr/local/www/wordpress
iocage fstab -a "${JAIL_NAME}" "${WP_PATH}"  /usr/local/www/wordpress  nullfs  rw  0  0

iocage exec "${JAIL_NAME}" mkdir -p /mnt/includes
iocage fstab -a "${JAIL_NAME}" "${INCLUDES_PATH}" /mnt/includes nullfs rw 0 0

#####
#
echo -e "${GREEN}Caddy download...${NOCOLOUR}"
#
#####

FILE="caddy_2.1.1_freebsd_amd64.tar.gz"
if ! iocage exec "${JAIL_NAME}" fetch -o /tmp https://github.com/caddyserver/caddy/releases/download/v2.1.1/"${FILE}"
then
	echo "Failed to download Caddy"
	exit 1
fi
if ! iocage exec "${JAIL_NAME}" tar xzf /tmp/"${FILE}" -C /usr/local/bin/
then
	echo "Failed to extract Caddy"
	exit 1
fi
iocage exec "${JAIL_NAME}" rm /tmp/"${FILE}"

#####
#
echo -e "${GREEN}Wordpress download...${NOCOLOUR}"  
#
#####

FILE="latest.tar.gz"
if ! iocage exec "${JAIL_NAME}" fetch -o /tmp https://wordpress.org/"${FILE}"
then
	echo "Failed to download WordPress"
	exit 1
fi
if ! iocage exec "${JAIL_NAME}" tar xzf /tmp/"${FILE}" -C /usr/local/www/
then
	echo "Failed to extract WordPress"
	exit 1
fi
iocage exec "${JAIL_NAME}" chown -R www:www /usr/local/www/wordpress

#####
#
echo -e "${GREEN}Configure and start Caddy...${NOCOLOUR}"
#
#####

# Copy and edit pre-written config files
iocage exec "${JAIL_NAME}" cp -f /mnt/includes/Caddyfile /usr/local/www
iocage exec "${JAIL_NAME}" cp -f /mnt/includes/caddy /usr/local/etc/rc.d/

iocage exec "${JAIL_NAME}" sysrc caddy_enable="YES"
iocage exec "${JAIL_NAME}" sysrc caddy_config="/usr/local/www/Caddyfile"

iocage exec "${JAIL_NAME}" service caddy start

#####
#
echo -e "${GREEN}Configure and start PHP-FPM...${NOCOLOUR}"
#
#####

# Copy and edit pre-written config files
iocage exec "${JAIL_NAME}" ln -s /usr/local/etc/php.ini-production /usr/local/etc/php.ini
##iocage exec "${JAIL_NAME}" cp -f /usr/local/etc/php-production.ini /usr/local/etc/php.ini
#iocage exec "${JAIL_NAME}" cp -f /mnt/includes/php.ini /usr/local/etc/php.ini
#iocage exec "${JAIL_NAME}" cp -f /mnt/includes/www.conf /usr/local/etc/php-fpm.d/

iocage exec "${JAIL_NAME}" sysrc php_fpm_enable="YES"

iocage exec "${JAIL_NAME}" service php-fpm start

#####
#
echo -e "${GREEN}Configure and start MariaDB...${NOCOLOUR}"
#
#####

# Copy and edit pre-written config files
#iocage exec "${JAIL_NAME}" cp -f /mnt/includes/my-system.cnf /var/db/mysql/my.cnf
#iocage exec "${JAIL_NAME}" sed -i '' "s|mytimezone|${TIME_ZONE}|" /usr/local/etc/php.ini

iocage exec "${JAIL_NAME}" sysrc mysql_enable="YES"

iocage exec "${JAIL_NAME}" chown mysql:mysql /var/run/mysql
iocage exec "${JAIL_NAME}" service mysql-server start

#####
#
echo -e "${GREEN}Create the WordPress database...${NOCOLOUR}"
#
#####

ADMIN_PASSWORD=$(openssl rand -base64 12)
DB_ROOT_PASSWORD=$(openssl rand -base64 16)
DB_PASSWORD=$(openssl rand -base64 16)

iocage exec "${JAIL_NAME}" mysql -u root -e "CREATE DATABASE wordpress;"
#iocage exec "${JAIL_NAME}" mysql -u root -e "GRANT ALL PRIVILEGES ON wordpress.* TO wordpress@localhost IDENTIFIED BY '${DB_PASSWORD}';"
iocage exec "${JAIL_NAME}" mysql -u root -e "GRANT ALL PRIVILEGES ON wordpress.* TO wordpress@localhost IDENTIFIED BY '123';"
iocage exec "${JAIL_NAME}" mysql -u root -e "FLUSH PRIVILEGES;"

#iocage exec "${JAIL_NAME}" mysqladmin --user=root password "${DB_ROOT_PASSWORD}" reload

# Save passwords for later reference
iocage exec "${JAIL_NAME}" echo "${DB_NAME} root password is ${DB_ROOT_PASSWORD}" > /root/${JAIL_NAME}_db_password.txt
iocage exec "${JAIL_NAME}" echo "Nextcloud database password is ${DB_PASSWORD}" >> /root/${JAIL_NAME}_db_password.txt
iocage exec "${JAIL_NAME}" echo "Nextcloud Administrator password is ${ADMIN_PASSWORD}" >> /root/${JAIL_NAME}_db_password.txt

#####
#
echo -e "${GREEN}Configure WordPress...${NOCOLOUR}"
#
#####

#iocage exec "${JAIL_NAME}" cp -f /usr/local/www/wordpress/wp-config-sample.php /usr/local/www/wordpress/wp-config.php
#iocage exec "${JAIL_NAME}" sed -i '' "s|database_name_here|wordpress|" /usr/local/www/wordpress/wp-config.php
#iocage exec "${JAIL_NAME}" sed -i '' "s|username_here|wordpress|" /usr/local/www/wordpress/wp-config.php
#iocage exec "${JAIL_NAME}" sed -i '' "s|password_here|${DB_PASSWORD}|" /usr/local/www/wordpress/wp-config.php

#####
#
echo -e "${GREEN}Installation complete!${NOCOLOUR}"
#
#####

echo "Default user is admin, password is ${ADMIN_PASSWORD}"
echo ""
echo "Database Information"
echo "--------------------"
echo "Database user = wordpress"
echo "Database password = ${DB_PASSWORD}"
echo "The ${DB_NAME} root password is ${DB_ROOT_PASSWORD}"
echo ""
echo "All passwords are saved in /root/${JAIL_NAME}_db_password.txt"









#iocage restart "${JAIL_NAME}"
#####
#
# Nextcloud Install 
#
#####

#iocage exec "${JAIL_NAME}" touch /var/log/nextcloud.log
#iocage exec "${JAIL_NAME}" chown www /var/log/nextcloud.log

# Skip generation of config and database for reinstall (this already exists when doing a reinstall)
#if [ "${REINSTALL}" == "true" ]; then
#	echo "Reinstall detected, skipping generation of new config and database"
#	if [ "${DATABASE}" = "mariadb" ]; then
#	iocage exec "${JAIL_NAME}" cp -f /mnt/includes/my.cnf /root/.my.cnf
#	iocage exec "${JAIL_NAME}" sed -i '' "s|mypassword|${DB_ROOT_PASSWORD}|" /root/.my.cnf
#	fi
#else

# Secure database, set root password, create Nextcloud DB, user, and password

#  iocage exec "${JAIL_NAME}" mysql -u root -e "CREATE DATABASE nextcloud;"
#  iocage exec "${JAIL_NAME}" mysql -u root -e "GRANT ALL ON nextcloud.* TO nextcloud@localhost IDENTIFIED BY '${DB_PASSWORD}';"
#  iocage exec "${JAIL_NAME}" mysql -u root -e "DELETE FROM mysql.user WHERE User='';"
#  iocage exec "${JAIL_NAME}" mysql -u root -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
#  iocage exec "${JAIL_NAME}" mysql -u root -e "DROP DATABASE IF EXISTS test;"
#  iocage exec "${JAIL_NAME}" mysql -u root -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
#  iocage exec "${JAIL_NAME}" mysqladmin --user=root password "${DB_ROOT_PASSWORD}" reload
##  iocage exec "${JAIL_NAME}" mysqladmin reload
#  iocage exec "${JAIL_NAME}" cp -f /mnt/includes/my.cnf /root/.my.cnf
#  iocage exec "${JAIL_NAME}" sed -i '' "s|mypassword|${DB_ROOT_PASSWORD}|" /root/.my.cnf


# Save passwords for later reference
#iocage exec "${JAIL_NAME}" echo "${DB_NAME} root password is ${DB_ROOT_PASSWORD}" > /root/${JAIL_NAME}_db_password.txt
#iocage exec "${JAIL_NAME}" echo "Nextcloud database password is ${DB_PASSWORD}" >> /root/${JAIL_NAME}_db_password.txt
#iocage exec "${JAIL_NAME}" echo "Nextcloud Administrator password is ${ADMIN_PASSWORD}" >> /root/${JAIL_NAME}_db_password.txt#

# CLI installation and configuration of Nextcloud

#if [ "${DATABASE}" = "mariadb" ]; then
#  iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ maintenance:install --database=\"mysql\" --database-name=\"nextcloud\" --database-user=\"nextcloud\" --database-pass=\"${DB_PASSWORD}\" --database-host=\"localhost:/tmp/mysql.sock\" --admin-user=\"admin\" --admin-pass=\"${ADMIN_PASSWORD}\" --data-dir=\"/mnt/files\""
#  iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set mysql.utf8mb4 --type boolean --value=\"true\""
#elif [ "${DATABASE}" = "pgsql" ]; then
#  iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ maintenance:install --database=\"pgsql\" --database-name=\"nextcloud\" --database-user=\"nextcloud\" --database-pass=\"${DB_PASSWORD}\" --database-host=\"localhost:/tmp/.s.PGSQL.5432\" --admin-user=\"admin\" --admin-pass=\"${ADMIN_PASSWORD}\" --data-dir=\"/mnt/files\""
#fi
#iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ db:add-missing-indices"
#iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ db:convert-filecache-bigint --no-interaction"
#iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set logtimezone --value=\"${TIME_ZONE}\""
#iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set log_type --value="file"'
#iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set logfile --value="/var/log/nextcloud.log"'
#iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set loglevel --value="2"'
#iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set logrotate_size --value="104847600"'
#iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set memcache.local --value="\OC\Memcache\APCu"'
#iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set redis host --value="/var/run/redis/redis.sock"'
#iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set redis port --value=0 --type=integer'
#iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set memcache.locking --value="\OC\Memcache\Redis"'
#iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set overwritehost --value=\"${HOST_NAME}\""
#if [ $NO_CERT -eq 1 ]; then
#  iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set overwrite.cli.url --value=\"http://${HOST_NAME}/\""
#  iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set overwriteprotocol --value=\"http\""
#else
#  iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set overwrite.cli.url --value=\"https://${HOST_NAME}/\""
#  iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set overwriteprotocol --value=\"https\""
#fi
#iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set htaccess.RewriteBase --value="/"'
#iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ maintenance:update:htaccess'
#iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set trusted_domains 1 --value=\"${HOST_NAME}\""
#iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set trusted_domains 2 --value=\"${IP}\""
##iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ app:enable encryption'
##iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ encryption:enable'
##iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ encryption:disable'
#iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ background:cron'
#fi

#iocage exec "${JAIL_NAME}" su -m www -c 'php -f /usr/local/www/nextcloud/cron.php'
#iocage exec "${JAIL_NAME}" crontab -u www /mnt/includes/www-crontab

# Add the www user to the redis group to allow it to access the socket
#iocage exec "${JAIL_NAME}" pw usermod www -G redis

# Don't need /mnt/includes any more, so unmount it
#iocage fstab -r "${JAIL_NAME}" "${INCLUDES_PATH}" /mnt/includes nullfs rw 0 0

#####
#
# Output results to console
#
#####

# Done!
#echo "Installation complete!"
#  echo "Using your web browser, go to http://${HOST_NAME} to log in"


#if [ "${REINSTALL}" == "true" ]; then
#	echo "You did a reinstall, please use your old database and account credentials"
#else

#	echo "Default user is admin, password is ${ADMIN_PASSWORD}"
#	echo ""
#	echo "Database Information"
#	echo "--------------------"
#	echo "Database user = nextcloud"
#	echo "Database password = ${DB_PASSWORD}"
#	echo "The ${DB_NAME} root password is ${DB_ROOT_PASSWORD}"
#	echo ""
#	echo "All passwords are saved in /root/${JAIL_NAME}_db_password.txt"
#fi
