# freenas-iocage-wordpress. Buggy. Do not use!!!

Under development

###Troubleshooting
1. Caddy - /var/log/caddy.log
2. PHP-FPM - /var/log/php-fpm.log
3. MariaDB - var/db/mysql/wordpress.err
4. WordPress - 

###Post-Installation Tasks

Do these within the jail.

1. Secure the database.

/usr/local/bin/mysql_secure_installation

2. Secret key generation. Update wp-config.php
https://api.wordpress.org/secret-key/1.1/salt/

3. Set up reverse proxy

4. Patch wp-config.php. See https://www.cloudbooklet.com/install-wordpress-with-nginx-reverse-proxy-to-apache-on-ubuntu-18-04-google-cloud/

5. Run WP configuration


5. Set up multisite (optional)

# freenas-iocage-wordpress
Script to create an iocage jail on FreeNAS for the latest WordPress release, including Caddy 2.1.1, MariaDB 7.3 and PHP74 scripting language.

This script will create an iocage jail on FreeNAS 11.3 or TrueNAS CORE 12.0 with the latest release of WordPress, along with its dependencies. It will configure the jail to store the database and WordPress data outside the jail, so it will not be lost in the event you need to rebuild the jail.

## Status
This script will work with FreeNAS 11.3, and it should also work with TrueNAS CORE 12.0.  Due to the EOL status of FreeBSD 11.2, it is unlikely to work reliably with earlier releases of FreeNAS.

## Usage

### Prerequisites (Reverse Proxy)
The WordPress jail created by this script is designed to work behind a reverse proxy.

### Prerequisites (Other)
Although not required, it's recommended to create a Dataset named `apps` with a sub-dataset named `wordpress` on your main storage pool and nested sub-datasets `files` and `db`.  Many other jail guides also store their configuration and data in subdirectories of `pool/apps/` 

For optimal performance, set the record size of the `db` dataset to 16 KB (under Advanced Settings in the FreeNAS web GUI).  It's also recommended to cache only metadata on the `db` dataset; you can do this by running `zfs set primarycache=metadata poolname/db`. 

If these datasets are not present, directories `/apps/wordpress/files` and `/apps/wordpress/db` will be created in `$POOL_PATH`.

### Installation
Download the repository to a convenient directory on your FreeNAS system by changing to that directory and running `git clone https://github.com/basilhendroff/freenas-iocage-wordpress`.  Then change into the new `freenas-iocage-wordpress` directory and create a file called `wordpress-config` with your favorite text editor.  In its minimal form, it would look like this:
```
JAIL_IP="192.168.1.4"
DEFAULT_GW_IP="192.168.1.1"
TIME_ZONE="Australia/Perth"
```
Many of the options are self-explanatory, and all should be adjusted to suit your needs, but only a few are mandatory.  The mandatory options are:

* JAIL_IP is the IP address for your jail.  You can optionally add the netmask in CIDR notation (e.g., 192.168.1.199/24).  If not specified, the netmask defaults to 24 bits.  Values of less than 8 bits or more than 30 bits are invalid.
* DEFAULT_GW_IP is the address for your default gateway
* TIME_ZONE is the time zone of your location, in PHP notation--see the [PHP manual](http://php.net/manual/en/timezones.php) for a list of all valid time zones.
 
In addition, there are some other options which have sensible defaults, but can be adjusted if needed. These are:

- JAIL_NAME: The name of the jail, defaults to `wordpress`.
- POOL_PATH: The path for your data pool. It is set automatically if left blank.
- FILES_PATH: WordPress site data is stored in this path; defaults to `$POOL_PATH/apps/wordpress/files`.
- DB_PATH: Selective backups are stored in this path; defaults to `$POOL_PATH/apps/wordpress/db`.
- INTERFACE: The network interface to use for the jail. Defaults to `vnet0`.
- VNET: Whether to use the iocage virtual network stack. Defaults to `on`.

### Execution
Once you've downloaded the script and prepared the configuration file, run this script (`script wordpress.log ./wordpress-jail.sh`).  The script will run for several minutes.  When it finishes, your jail will be created, and WordPress will be installed with all its dependencies. Next, you must set up the WordPress jail behind your reverse proxy. You can configure WordPress using the FQDN for the jail. Do not attempt to configure WordPress via the jail IP address. 

### To Do
I'd appreciate any suggestions (or, better yet, pull requests) to improve the various config files I'm using.  Most of them are adapted from the default configuration files that ship with the software in question, and have only been lightly edited to work in this application.  But if there are changes to settings or organization that could improve performance, reliability, or security, I'd like to hear about them.
