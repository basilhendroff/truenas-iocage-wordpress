#!/bin/bash
# Build an iocage jail under FreeNAS 11.3-12.0 using the latest release of WordPress
# git clone https://github.com/basilhendroff/freenas-iocage-wordpress

print_msg () {
  echo
  echo -e "\e[1;32m"$1"\e[0m"
  echo
}

print_err () {
  echo -e "\e[1;31m"$1"\e[0m"
  echo
}

rand() {
  local rnum=$(LC_ALL=C tr -dc 'A-Za-z0-9!#%()*+,-./:;<=>?@[]^_{}~' </dev/urandom | head -c "$1" ; echo)
  echo $rnum
}

# Check for root privileges
if ! [ $(id -u) = 0 ]; then
  print_err "This script must be run with root privileges" 
  exit 1
fi

#####################################################################
print_msg "General configuration..."

# Initialize defaults
JAIL_IP=""
JAIL_INTERFACES=""
DEFAULT_GW_IP=""
INTERFACE="vnet0"
VNET="on"
POOL_PATH=""
JAIL_NAME="wordpress"
TIME_ZONE=""
WP_ROOT="/apps/wordpress"
CONFIG_NAME="wordpress-config"

# Exposed configuration parameters
# php.ini
UPLOAD_MAX_FILESIZE="32M"	# default=2M
POST_MAX_SIZE="48M"		# default=8M
MEMORY_LIMIT="256M"		# default=128M
MAX_EXECUTION_TIME=600		# default=30 seconds
MAX_INPUT_VARS=3000		# default=1000
MAX_INPUT_TIME=1000		# default=60 seconds

# Check for wordpress-config and set configuration
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "${SCRIPT}")
if ! [ -e "${SCRIPTPATH}"/"${CONFIG_NAME}" ]; then
  print_err "${SCRIPTPATH}/${CONFIG_NAME} must exist."
  exit 1
fi
. "${SCRIPTPATH}"/"${CONFIG_NAME}"
INCLUDES_PATH="${SCRIPTPATH}"/includes

RELEASE=$(freebsd-version | cut -d - -f -1)"-RELEASE"

#####################################################################
print_msg "Input/Config Sanity checks..."

# Check that necessary variables were set by nextcloud-config
if [ -z "${JAIL_IP}" ]; then
  print_err 'Configuration error: JAIL_IP must be set'
  exit 1
fi
if [ -z "${JAIL_INTERFACES}" ]; then
  print_msg 'JAIL_INTERFACES defaulting to: vnet0:bridge0'
  JAIL_INTERFACES="vnet0:bridge0"
fi
if [ -z "${DEFAULT_GW_IP}" ]; then
  print_err 'Configuration error: DEFAULT_GW_IP must be set'
  exit 1
fi
if [ -z "${POOL_PATH}" ]; then
  POOL_PATH="/mnt/$(iocage get -p)"
  print_msg 'POOL_PATH defaulting to '$POOL_PATH
fi
if [ -z "${TIME_ZONE}" ]; then
  print_err 'Configuration error: TIME_ZONE must be set'
  exit 1
fi

if [ -n "${FILES_PATH}" ] || [ -n "${DB_PATH}" ]; then
  print_err "Configuration error: WP_ROOT replaces FILES_PATH and DB_PATH in newer script versions. Update ${CONFIG_NAME} and run the script again."
  exit 1
fi
if [ ${WP_ROOT:0:1} != "/" ]; then
  WP_ROOT="/${WP_ROOT}"
fi
WP_ROOT="${WP_ROOT%/}"
mkdir -p "${POOL_PATH}${WP_ROOT}"
DB_PATH=${POOL_PATH}${WP_ROOT}/db
FILES_PATH=${POOL_PATH}${WP_ROOT}/files

# Check that this is a new installation
if [ "$(ls -A "${FILES_PATH}")" ] || [ "$(ls -A "${DB_PATH}")" ]
then
  print_err "This script only works for new installations. The script cannot proceed if ${FILES_PATH} and ${DB_PATH} are not both empty."
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

# Reuse the password file if it exists and is valid
if ! [ -e "/root/${JAIL_NAME}_db_password.txt" ]; then
  DB_PASSWORD=$(rand 24)

  # Save passwords for later reference
  echo 'DB_PASSWORD="'${DB_PASSWORD}'" # user=wordpress' > /root/${JAIL_NAME}_db_password.txt


ls else
  # Check for the existence of password variables
  . "/root/${JAIL_NAME}_db_password.txt"
  if [ -z "${DB_PASSWORD}" ]; then
    print_err "/root/${JAIL_NAME}_db_password.txt is corrupt."
    exit 1
  fi
  if [ -n "${DB_ROOT_PASSWORD}" ]; then
    print_err "If using the new authentication scheme in MariaDB 10.4 and above, the DB_ROOT_PASSWORD in /root/${JAIL_NAME}_db_password.txt becomes redundant."
  fi  
# Backup the password file to WP_ROOT
  cp /root/${JAIL_NAME}_db_password.txt ${POOL_PATH}${WP_ROOT}
fi

#####################################################################
print_msg "Jail Creation. Time for a cuppa. Installing packages will take a while..."

# List packages to be auto-installed after jail creation

cat <<__EOF__ >/tmp/pkg.json
	{
  "pkgs":[
  "php74","php74-curl","php74-dom","php74-exif","php74-fileinfo","php74-json","php74-mbstring",
  "php74-mysqli","php74-pecl-libsodium","php74-openssl","php74-pecl-imagick","php74-xml","php74-zip",
  "php74-filter","php74-gd","php74-iconv","php74-pecl-mcrypt","php74-simplexml","php74-xmlreader","php74-zlib",
  "php74-ftp","php74-pecl-ssh2","php74-sockets",
  "mariadb105-server","unix2dos","ssmtp","phpmyadmin5-php74",
  "php74-xmlrpc","php74-ctype","php74-session","php74-xmlwriter",
  "redis","php74-pecl-redis","php74-phar","caddy"
  ]
}
__EOF__

# Create the jail and install previously listed packages
if ! iocage create --name "${JAIL_NAME}" -p /tmp/pkg.json -r "${RELEASE}" interfaces="${JAIL_INTERFACES}" ip4_addr="${INTERFACE}|${IP}/${NETMASK}" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}" vnet="${VNET}"
then
  print_err "Failed to create jail"
  exit 1
fi
rm /tmp/pkg.json

#####################################################################
print_msg "Directory Creation and Mounting..."

mkdir -p "${DB_PATH}"
chown -R 88:88 "${DB_PATH}"
iocage fstab -a "${JAIL_NAME}" "${DB_PATH}"  /var/db/mysql  nullfs  rw  0  0

mkdir -p "${FILES_PATH}"
chown -R 80:80 "${FILES_PATH}"
iocage exec "${JAIL_NAME}" mkdir -p /usr/local/www/wordpress
iocage fstab -a "${JAIL_NAME}" "${FILES_PATH}"  /usr/local/www/wordpress  nullfs  rw  0  0

iocage exec "${JAIL_NAME}" mkdir -p /mnt/includes
iocage fstab -a "${JAIL_NAME}" "${INCLUDES_PATH}" /mnt/includes nullfs rw 0 0

#####################################################################
print_msg "Wordpress download..."  

FILE="latest.tar.gz"
if ! iocage exec "${JAIL_NAME}" fetch -o /tmp https://wordpress.org/"${FILE}"
then
  print_err "Failed to download WordPress"
  exit 1
fi
if ! iocage exec "${JAIL_NAME}" tar xzf /tmp/"${FILE}" -C /usr/local/www/
then
  print_err "Failed to extract WordPress"
  exit 1
fi
iocage exec "${JAIL_NAME}" rm /tmp/"${FILE}"
iocage exec "${JAIL_NAME}" chown -R www:www /usr/local/www/wordpress

#####################################################################
print_msg "Enable phpMyAdmin..."

iocage exec "${JAIL_NAME}" rm /usr/local/www/phpMyAdmin/config.inc.php
iocage exec "${JAIL_NAME}" ln -s /usr/local/www/phpMyAdmin /usr/local/www/wordpress/phpmyadmin

# Copy and edit pre-written config file
iocage exec "${JAIL_NAME}" cp -f /usr/local/www/phpMyAdmin/config.sample.inc.php /usr/local/www/phpMyAdmin/config.inc.php
iocage exec "${JAIL_NAME}" sed -i '' "s|\$cfg\['blowfish_secret'\] = ''|\$cfg\['blowfish_secret'\] = '$(rand 32)'|" /usr/local/www/phpMyAdmin/config.inc.php

#####################################################################
print_msg "Configure and start PHP-FPM..."

# Copy and edit pre-written config file
iocage exec "${JAIL_NAME}" cp -f /usr/local/etc/php.ini-production /usr/local/etc/php.ini
iocage exec "${JAIL_NAME}" sed -i '' "s|upload_max_filesize = 2M|upload_max_filesize = ${UPLOAD_MAX_FILESIZE}|" /usr/local/etc/php.ini
iocage exec "${JAIL_NAME}" sed -i '' "s|post_max_size = 8M|post_max_size = ${POST_MAX_SIZE}|" /usr/local/etc/php.ini
iocage exec "${JAIL_NAME}" sed -i '' "s|memory_limit = 128M|memory_limit = ${MEMORY_LIMIT}|" /usr/local/etc/php.ini
iocage exec "${JAIL_NAME}" sed -i '' "s|max_execution_time = 30|max_execution_time = ${MAX_EXECUTION_TIME}|" /usr/local/etc/php.ini
iocage exec "${JAIL_NAME}" sed -i '' "s|;max_input_vars = 1000|max_input_vars = ${MAX_INPUT_VARS}|" /usr/local/etc/php.ini
iocage exec "${JAIL_NAME}" sed -i '' "s|max_input_time = 60|max_input_time = ${MAX_INPUT_TIME}|" /usr/local/etc/php.ini
iocage exec "${JAIL_NAME}" sed -i '' "s|;date.timezone =|date.timezone = ${TIME_ZONE}|" /usr/local/etc/php.ini

# MariaDB 10.4 requirement
iocage exec "${JAIL_NAME}" sed -i '' "s|mysqli.default_socket =|mysqli.default_socket = /var/run/mysql/mysql.sock|" /usr/local/etc/php.ini

iocage exec "${JAIL_NAME}" sysrc php_fpm_enable="YES"
iocage exec "${JAIL_NAME}" service php-fpm start

#####################################################################
print_msg "Configure and start MariaDB..."

iocage exec "${JAIL_NAME}" sysrc mysql_enable="YES"
iocage exec "${JAIL_NAME}" service mysql-server start

#####################################################################
print_msg "Create and secure the WordPress and phpMyAdmin databases..."

# Create the database.
iocage exec "${JAIL_NAME}" mysql -e "CREATE DATABASE wordpress;"
iocage exec "${JAIL_NAME}" mysql -e "GRANT ALL PRIVILEGES ON wordpress.* TO wordpress@localhost IDENTIFIED BY '${DB_PASSWORD}';"

# Create the phpMyAdmin database.
iocage exec "${JAIL_NAME}" mysql -e "CREATE DATABASE phpmyadmin;"
iocage exec "${JAIL_NAME}" mysql -e "GRANT ALL PRIVILEGES ON phpmyadmin.* TO wordpress@localhost IDENTIFIED BY '${DB_PASSWORD}';"

# Secure the database (equivalent of running /usr/local/bin/mysql_secure_installation)
# Remove anonymous users
iocage exec "${JAIL_NAME}" mysql -e "DELETE FROM mysql.user WHERE User='';"
# Disallow remote root login
iocage exec "${JAIL_NAME}" mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
# Remove test database and access to it
iocage exec "${JAIL_NAME}" mysql -e "DROP DATABASE IF EXISTS test;"
iocage exec "${JAIL_NAME}" mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
# Reload privilege tables
iocage exec "${JAIL_NAME}" mysql -e "FLUSH PRIVILEGES;"

#####################################################################
print_msg "Configure WordPress..."

iocage exec "${JAIL_NAME}" cp -f /usr/local/www/wordpress/wp-config-sample.php /usr/local/www/wordpress/wp-config.php
iocage exec "${JAIL_NAME}" dos2unix /usr/local/www/wordpress/wp-config.php
iocage exec "${JAIL_NAME}" sed -i '' "s|database_name_here|wordpress|" /usr/local/www/wordpress/wp-config.php
iocage exec "${JAIL_NAME}" sed -i '' "s|username_here|wordpress|" /usr/local/www/wordpress/wp-config.php
iocage exec "${JAIL_NAME}" sed -i '' "s|password_here|${DB_PASSWORD}|" /usr/local/www/wordpress/wp-config.php

print_msg "Tweak /usr/local/www/wordpress/wp-config.php..."
iocage exec "${JAIL_NAME}" /usr/local/bin/bash /mnt/includes/wp-config.sh

#####################################################################
print_msg "Configure and start REDIS..."

# Edit pre-written config files
iocage exec "${JAIL_NAME}" sed -i '' "s|port 6379|port 0|" /usr/local/etc/redis.conf
iocage exec "${JAIL_NAME}" sed -i '' "s|# unixsocket /tmp/redis.sock|unixsocket /var/run/redis/redis.sock|" /usr/local/etc/redis.conf
iocage exec "${JAIL_NAME}" sed -i '' "s|# unixsocketperm 700|unixsocketperm 770|" /usr/local/etc/redis.conf

iocage exec "${JAIL_NAME}" sysrc redis_enable="YES"
iocage exec "${JAIL_NAME}" service redis start

iocage exec "${JAIL_NAME}" pw usermod www -G redis

#####################################################################
print_msg "Install the command line tool WP-CLI..."

iocage exec "${JAIL_NAME}" curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
iocage exec "${JAIL_NAME}" chmod +x wp-cli.phar
iocage exec "${JAIL_NAME}" mv wp-cli.phar /usr/local/bin/wp

#####################################################################
print_msg "Configure sSMTP..."

iocage exec "${JAIL_NAME}" pw useradd ssmtp -g nogroup -h - -s /sbin/nologin -d /nonexistent -c "sSMTP pseudo-user"
iocage exec "${JAIL_NAME}" chown ssmtp:wheel /usr/local/etc/ssmtp
iocage exec "${JAIL_NAME}" chmod 4750 /usr/local/etc/ssmtp
iocage exec "${JAIL_NAME}" cp /usr/local/etc/ssmtp/ssmtp.conf.sample /usr/local/etc/ssmtp/ssmtp.conf
iocage exec "${JAIL_NAME}" cp /usr/local/etc/ssmtp/revaliases.sample /usr/local/etc/ssmtp/revaliases
iocage exec "${JAIL_NAME}" chown ssmtp:wheel /usr/local/etc/ssmtp/ssmtp.conf
iocage exec "${JAIL_NAME}" chmod 640 /usr/local/etc/ssmtp/ssmtp.conf
iocage exec "${JAIL_NAME}" chown ssmtp:nogroup /usr/local/sbin/ssmtp
iocage exec "${JAIL_NAME}" chmod 4555 /usr/local/sbin/ssmtp

print_msg "Tweak /etc/mail/mailer.conf..."
iocage exec "${JAIL_NAME}" /usr/local/bin/bash /mnt/includes/mailer.sh

#####################################################################
print_msg "Configure and start Caddy..."

# Copy and edit pre-written config files
iocage exec "${JAIL_NAME}" cp -f /mnt/includes/Caddyfile /usr/local/www
 
iocage exec "${JAIL_NAME}" sysrc caddy_enable="YES"
iocage exec "${JAIL_NAME}" sysrc caddy_config="/usr/local/www/Caddyfile"

iocage exec "${JAIL_NAME}" service caddy start

#####################################################################
print_msg "Installation complete!"

# Don't need /mnt/includes any more, so unmount it
iocage fstab -r "${JAIL_NAME}" "${INCLUDES_PATH}" /mnt/includes nullfs rw 0 0

#cat /root/${JAIL_NAME}_db_password.txt
print_msg "The WordPress database user password is saved in /root/${JAIL_NAME}_db_password.txt. Don't forget to backup this file."
print_msg "Continue with the post installation steps at https://github.com/basilhendroff/freenas-iocage-wordpress/blob/master/POST-INSTALL.md"
