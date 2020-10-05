## Manual Post-Installation Tasks
Assuming your WordPress jail is named `wordpress`, note the DB root password `cat /root/wordpress_db_password.txt`. You will need this to secure the MariaDB.

To complete the following tasks, use a terminal to connect to the jail `iocage console wordpress`.

1. Securing MariaDB
2. Authentication Unique Keys and Salts
3. Configure WordPress for Reverse Proxy
4. Setup the WordPress Filesystem
5. Configure Redis
6. Configure sSMTP
7. Test sSMTP
8. Configure phpMyAdmin

There is the opportunity to incorporate some of the above within the WordPress script. For more information, refer to the blog post [WordPress Script: Opportunities for Improvement](https://blog.udance.com.au/2020/09/20/wordpress-script-opportunities-for-improvement/).

### 1. Securing MariaDB
Run the script `/usr/local/bin/mysql_secure_installation`.

### 2. Authentication Unique Keys and Salts
Click on https://api.wordpress.org/secret-key/1.1/salt/ and then replace the relevant section in `wp-config.php`:

`cd /usr/local/www/wordpress && ee wp-config.php`

### 3. Configure WordPress for Reverse Proxy
Edit wp-config.php `cd /usr/local/www/wordpress && ee wp-config.php` 

Add these line to the top of the file below `<?php`.
```
define('FORCE_SSL_ADMIN', true); 
if (strpos($_SERVER['HTTP_X_FORWARDED_PROTO'], 'https') !== false)
  $_SERVER['HTTPS']='on';
```

### 4. Setup the WordPress Filesystem
Find the line `define('DB_PASSWORD', 'password');` in the file `wp-config.php` and paste the following line below it.

`define('FS_METHOD', 'direct');`

### 5. Configure Redis
Add the following code above the line `/* That's all, stop editing! Happy publishing. */`.
```
/* Set up Redis */
define( 'WP_REDIS_SCHEME', 'unix' );
define( 'WP_REDIS_PATH', '/var/run/redis/redis.sock' );
define( 'WP_REDIS_CLIENT', 'phpredis' );
```
Now save the file.

Note: For WordPress to use Redis, install and activate the Redis Object Cache plugin. Using the plugin, `Enable Object Cache `.  

### 6. Configure sSMTP
First, edit the file  `/etc/mail/mailer.conf`:

`cd /etc/mail && ee mailer.conf`

Locate the following lines:
```
sendmail        /usr/libexec/sendmail/sendmail
mailq           /usr/libexec/sendmail/sendmail
newaliases      /usr/libexec/sendmail/sendmail
hoststat        /usr/libexec/sendmail/sendmail
purgestat       /usr/libexec/sendmail/sendmail
```
Replace these lines with:
```
sendmail        /usr/local/sbin/ssmtp
send-mail       /usr/local/sbin/ssmtp
mailq           /usr/local/sbin/ssmtp
newaliases      /usr/local/sbin/ssmtp
hoststat        /usr/bin/true
purgestat       /usr/bin/true
```
Save the file.

Now edit the file `/usr/local/etc/ssmtp/ssmtp.conf`:

`cd /usr/local/etc/ssmtp && ee ssmtp.conf`

Enter your configuration details in the `ssmtp.conf` file. Modify this example to fit your situation:
```
MailHub=mail.example.com:465     # Mail server to connect to (port 465 is SMTP/SSL)
UseTLS=YES                       # Enable SSL/TLS 
AuthUser=john                    # Username for SMTP AUTH
AuthPass=Secret1                 # Password for SMTP AUTH 
FromLineOverride=YES             # Force the From: address to the user account 
Hostname=myhost.example.com      # Name of this host 
RewriteDomain=myhost.example.com # Where the mail will seem to come from 
Root=postmaster                  # Mail for root@ is redirected to postmaster@
```

### 7. Test sSMTP
Create a txt file `ee test.txt` with the following text, but remember to alter the email addresses.
```
To: yourmail@gmail.com 
From: yourmail@gmail.com 
Subject: Testmessage 
This is a test for sending
```
Run the command:

`ssmtp -v yourmail@gmail.com < test.txt`

Status messages should indicated that the mail was sent successfully. If there are no errors, you can then check out `yourmail@gmail.com` and make sure that email has been delivered successfully. But, if you do get errors, recheck your configuration settings in `/usr/local/etc/ssmtp/ssmtp.conf`. If you don't receive the email then check `/var/log/maillog`:

`cat /var/log/maillog`

Don't exit the jail just yet.

### 8. Configure phpMyAdmin
From a browser, use the WordPress jail IP to go to the address `http://jail_ip/phpmyadmin/setup` and configure a database server host.

Click `New server`.

Click `Apply`.

Click `Display`.

Copy the text of the generated configuration file and paste it into the file `/usr/local/www/phpMyAdmin/config.inc.php`.

`cd /usr/local/www/phpMyAdmin && ee config.inc.php`

Save the file and then exit the jail `exit`.

Note: Once you've placed the WordPress jail behind the reverse proxy, you will be able to log in to phpMyAdmin, with your database root username and password, using the jail FQDN instead of the jail IP e.g. `https://blog.mydomain.com/phpmyadmin`. I recommend you set up WordPress beforehand so you have something meaningful to look at in phpMyAdmin. 

**CAUTION**
>SECURITY NOTE: phpMyAdmin is an administrative tool that has had several remote vulnerabilities discovered in the past, some allowing remote attackers to execute arbitrary code with the web server's user credential. All known problems have been fixed, but the FreeBSD Security Team strongly advises that any instance be protected with an additional protection layer, e.g. a different access control mechanism implemented by the web server as shown in the example.  Do consider enabling phpMyAdmin only when it is in use.

One way to disable phpMyAdmin is to unlink it in the jail `rm /usr/local/www/wordpress/phpmyadmin`. This will disable access to phpMyAdmin via the well-known subdirectory path e.g. `https://blog.mydomain.com/phpmyadmin`. To reenable phpMyAdmin, link the subdirectory path again `ln -s /usr/local/www/phpMyAdmin /usr/local/www/wordpress/phpmyadmin`. Disable it again when finished.

Refer to [Securing your phpMyAdmin installation](https://docs.phpmyadmin.net/en/latest/setup.html#securing) for other means of securing phpMyAdmin.

## Configure the Reverse Proxy
If using Caddy, the code block might look something like:
```
blog.mydomain.com {
  encode gzip
  reverse_proxy http://192.168.1.4
}
```

## Set up WordPress
You're now ready to do the famous five-minute WordPress installation. Do this by entering your WordPress site FQDN in a browser e.g. https://blog.mydomain.com

## References
1. [How to install WordPress](https://wordpress.org/support/article/how-to-install-wordpress/)
2. [Install WordPress with Nginx Reverse Proxy to Apache on Ubuntu 18.04 – Google Cloud](https://www.cloudbooklet.com/install-wordpress-with-nginx-reverse-proxy-to-apache-on-ubuntu-18-04-google-cloud/)
3. [SecureSSMTP](https://wiki.freebsd.org/SecureSSMTP)
4. [Using Gmail SMTP to send email in FreeBSD](http://easyos.net/articles/bsd/freebsd/using_gmail_smtp_to_send_email_in_freebsd)
5. [Requirements — phpMyAdmin 5.1.0-dev documentation](https://docs.phpmyadmin.net/en/latest/require.html)
6. [Mujahid Jaleel - My Life, My Blog](https://mujahidjaleel.blogspot.com/2018/10/how-to-setup-phpmyadmin-in-iocage-jail.html)
7. [Caching and Redis: Samuel Dowling - How to Install Nextcloud on FreeNAS in an iocage Jail with Hardened Security](https://www.samueldowling.com/2020/07/24/install-nextcloud-on-freenas-iocage-jail-with-hardened-security/)
8. [Redis Object Cache plugin for WordPress - Till Kruss](https://wordpress.org/plugins/redis-cache/)
9. [How to Improve Your Site Performance Using Redis Cache on WordPress](https://www.cloudways.com/blog/install-redis-cache-wordpress/)
