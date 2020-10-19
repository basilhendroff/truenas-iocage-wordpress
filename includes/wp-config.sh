#!usr/local/bin/bash 
infile="/usr/local/www/wordpress/wp-config.php"
outfile="/usr/local/www/wordpress/wp-config.tmp"
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
    *)
      printf '%s\n' "$line" >> $outfile
      ;;
  esac
done
mv $outfile $infile
