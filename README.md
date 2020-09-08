# freenas-iocage-wordpress

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

4. Patch wp-config.php. See 


5. Set up multisite (optional)
