#!/usr/local/bin/bash
infile="/etc/mail/mailer.conf"
outfile="/etc/mail/mailer.tmp"
#rm $outfile
cat $infile | while IFS= read -r line; do
  case ${line:0:5} in
    sendm)
      printf '%s\t%s\n' "sendmail" "/usr/local/sbin/ssmtp" >> $outfile
      printf '%s\t%s\n' "send-mail" "/usr/local/sbin/ssmtp" >> $outfile
     ;;
    mailq)
      printf '%s\t\t%s\n' "mailq" "/usr/local/sbin/ssmtp" >> $outfile
      ;;
    newal)
      printf '%s\t%s\n' "newaliases" "/usr/local/sbin/ssmtp" >> $outfile
      ;;
    hosts)
      printf '%s\t%s\n' "hoststat" "/usr/bin/true" >> $outfile
      ;;
    purge)
      printf '%s\t%s\n' "purgestat" "/usr/bin/true" >> $outfile
      ;;
    *)
      printf '%s\n' "$line" >> $outfile
      ;;
  esac
done
mv $infile /etc/mail/mailer-sample.conf
mv $outfile $infile
