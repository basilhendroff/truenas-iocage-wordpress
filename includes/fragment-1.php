
// Using a reverse proxy.
define('FORCE_SSL_ADMIN', true);
if (strpos($_SERVER['HTTP_X_FORWARDED_PROTO'], 'https') !== false)
  $_SERVER['HTTPS']='on';
