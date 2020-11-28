#!usr/local/bin/bash 

# File pointers
infile="/usr/local/www/wordpress/wp-config.php"
outfile="/usr/local/www/wordpress/wp-config.tmp"

# Random password generator (allow additional special characters ampersand (&), space ( ) and pipe symbol (|))
rand() {
  local rnum=$(LC_ALL=C tr -dc 'A-Za-z0-9 !#$%&()*+,-./:;<=>?@[]^_`{|}~' </dev/urandom | head -c "$1" ; echo)
  echo $rnum
}

# wp-config.php adjustments
cat $infile | while IFS= read -r line; do
  case $line in
    "<?php")
      printf '%s\n' "$line" >> $outfile
      cat /mnt/includes/fragment-1.php | while IFS= read -r frag; do
        printf '%s\n' "$frag" >> $outfile
      done 
      ;;
    *DB_PASSWORD*)
      printf '%s\n' "$line" >> $outfile
      cat /mnt/includes/fragment-2.php | while IFS= read -r frag; do
        printf '%s\n' "$frag" >> $outfile
      done
      ;;
    "/* That's all, stop editing! Happy publishing. */")
      cat /mnt/includes/fragment-3.php | while IFS= read -r frag; do
        printf '%s\n' "$frag" >> $outfile
      done
      printf '%s\n' "$line" >> $outfile
      ;;
    *'SECURE_AUTH_KEY'*)
      printf "define( 'SECURE_AUTH_KEY',  '%s' );\n" "$(rand 64)" >> $outfile
      ;;
    *'AUTH_KEY'*)
      printf "define( 'AUTH_KEY',         '%s' );\n" "$(rand 64)" >> $outfile
      ;;
    *'LOGGED_IN_KEY'*)
      printf "define( 'LOGGED_IN_KEY',    '%s' );\n" "$(rand 64)" >> $outfile
      ;;
    *'NONCE_KEY'*)
      printf "define( 'NONCE_KEY',        '%s' );\n" "$(rand 64)" >> $outfile
      ;;
    *'SECURE_AUTH_SALT'*)
      printf "define( 'SECURE_AUTH_SALT', '%s' );\n" "$(rand 64)" >> $outfile
      ;;
    *'AUTH_SALT'*)
      printf "define( 'AUTH_SALT',        '%s' );\n" "$(rand 64)" >> $outfile
      ;;
    *'LOGGED_IN_SALT'*)
      printf "define( 'LOGGED_IN_SALT',   '%s' );\n" "$(rand 64)" >> $outfile
      ;;
    *'NONCE_SALT'*)
      printf "define( 'NONCE_SALT',       '%s' );\n" "$(rand 64)" >> $outfile
      ;;
    *)
      printf '%s\n' "$line" >> $outfile
      ;;
  esac
done
mv $outfile $infile
