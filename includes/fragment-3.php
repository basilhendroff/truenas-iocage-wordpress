if ( WP_DEBUG ) {
  @error_reporting( E_ALL );
  @ini_set( 'log_errors', true );
  @ini_set( 'log_errors_max_len', '0' );

  define( 'WP_DEBUG_LOG', true );
  define( 'WP_DEBUG_DISPLAY', false );
  define( 'CONCATENATE_SCRIPTS', false );
  define( 'SAVEQUERIES', true );
}

// WP Super Cache plugin support.
define('WP_CACHE', true);
define ('WPCACHEHOME', '/usr/local/www/wordpress/wp-content/plugins/wp-super-cache/');

// Redis plugin support.
define( 'WP_REDIS_SCHEME', 'unix' );
define( 'WP_REDIS_PATH', '/var/run/redis/redis.sock' );
define( 'WP_REDIS_CLIENT', 'phpredis' );
