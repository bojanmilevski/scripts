#!/bin/sh

# REFENRENCES
#
# Luke Smith: Setting up a Website and Email Server in One Sitting
# https://www.youtube.com/watch?v=3dIVesHEAzc
#
# Luke Smith's emailwiz.sh script
# https://github.com/LukeSmithxyz/emailwiz/blob/master/emailwiz.sh
#
# David Luevano's Arch Linux emailwiz.sh rewrite
# https://blog.luevano.xyz/a/mail_server_with_postfix

set -e

source "$(basename "$0")/header.sh"

umask 0022

domain=""
user_name=""

[ -z "$domain" ] && echo "Specify domain name!" && exit 1
[ -z "$user_name" ] && echo "Specify user name!" && exit 1

subdom="mail"
maildomain="$subdom.$domain"

certdir="/etc/letsencrypt/live/$maildomain"
postfix_dir="/var/spool/postfix"

message() {
	echo "${BOLD}${GREEN}CONFIGURING ${1}${RESET}"
}

copy() {
	dir=$(dirname "$1")
	pat=$(basename "$1")
	lr=$(find "$dir" -maxdepth 1 -name "$pat")
	if test ! -d "$2"; then exit 1; fi
	if test "x$lr" != "x"; then cp -p "$1" "$2"; fi
}

# install packages
apk add postfix postfix-openrc postfix-pcre dovecot dovecot-openrc dovecot-pigeonhole-plugin \
	dovecot-pigeonhole-plugin-ldap dovecot-pop3d opendkim opendkim-utils spamassassin \
	spamassassin-openrc spamassassin-client net-tools fail2ban fail2ban-openrc nginx certbot \
	certbot-nginx

echo "server {
	listen 443 ssl;
	listen [::]:443 ssl;

	server_name $maildomain www.$maildomain;

	location / {
		return 404;
	}
}" >"/etc/nginx/http.d/mail.conf"

[ ! -d "$certdir" ] &&
	possiblecert="$(certbot certificates 2>/dev/null | grep "Domains:\.* \(\*\.$domain\|$maildomain\)\(\s\|$\)" -A 2 | awk '/Certificate Path/ {print $3}' | head -n1)" &&
	certdir="${possiblecert%/*}"

[ ! -d "$certdir" ] &&
	certdir="/etc/letsencrypt/live/$maildomain" &&
	certbot certonly -d "$maildomain" -d "www.$maildomain" --nginx --register-unsafely-without-email --agree-tos --non-interactive

[ ! -d "$certdir" ] && echo "Error locating or installing SSL certificate." && exit 1

message "/etc/postfix/main.cf"

# Adding additional vars to fix an issue with receiving emails (relay access denied) and adding it to mydestination.
postconf -e "myhostname = $maildomain"
postconf -e "mail_name = $domain" #This is for the smtpd_banner
postconf -e "mydomain = $domain"
postconf -e 'mydestination = $myhostname, $mydomain, mail, localhost.localdomain, localhost, localhost.$mydomain'

# Change the cert/key files to the default locations of the Let's Encrypt cert/key
postconf -e "smtpd_tls_key_file=$certdir/privkey.pem"
postconf -e "smtpd_tls_cert_file=$certdir/fullchain.pem"
postconf -e "smtp_tls_CAfile=$certdir/cert.pem"

# Enable, but do not require TLS. Requiring it with other server would cause
# mail delivery problems and requiring it locally would cause many other
# issues.
postconf -e "smtpd_tls_security_level = may"
postconf -e "smtp_tls_security_level = may"

# TLS required for authentication.
postconf -e "smtpd_tls_auth_only = yes"

# Exclude obsolete, insecure and obsolete encryption protocols.
postconf -e 'smtpd_tls_mandatory_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1'
postconf -e 'smtp_tls_mandatory_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1'
postconf -e 'smtpd_tls_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1'
postconf -e 'smtp_tls_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1'

# Exclude suboptimal ciphers.
postconf -e "tls_preempt_cipherlist = yes"
postconf -e "smtpd_tls_exclude_ciphers = aNULL, LOW, EXP, MEDIUM, ADH, AECDH, MD5, DSS, ECDSA, CAMELLIA128, 3DES, CAMELLIA256, RSA+AES, eNULL" # causes problems, i tend to comment this line out

# Here we tell Postfix to look to Dovecot for authenticating users/passwords.
# Dovecot will be putting an authentication socket in /var/spool/postfix/private/auth
postconf -e "smtpd_sasl_auth_enable = yes"
postconf -e "smtpd_sasl_type = dovecot"
postconf -e "smtpd_sasl_path = private/auth"

# helo, sender, relay and recipient restrictions
postconf -e "smtpd_sender_login_maps = pcre:/etc/postfix/login_maps.pcre"
postconf -e "smtpd_sender_restrictions = permit_sasl_authenticated, permit_mynetworks, reject_sender_login_mismatch, reject_unknown_reverse_client_hostname, reject_unknown_sender_domain"
postconf -e "smtpd_recipient_restrictions = permit_sasl_authenticated, permit_mynetworks, reject_unauth_destination, reject_unknown_recipient_domain"
postconf -e "smtpd_relay_restrictions = permit_sasl_authenticated, reject_unauth_destination"
postconf -e "smtpd_helo_required = yes"
postconf -e "smtpd_helo_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_invalid_helo_hostname, reject_non_fqdn_helo_hostname, reject_unknown_helo_hostname"

# NOTE: the trailing slash here, or for any directory name in the home_mailbox
# command, is necessary as it distinguishes a maildir (which is the actual
# directories that what we want) from a spoolfile (which is what old unix
# boomers want and no one else).
postconf -e "home_mailbox = Mail/Inbox/"

# Prevent "Received From:" header in sent emails in order to prevent leakage of public ip addresses
postconf -e "header_checks = regexp:/etc/postfix/header_checks"

# Here we add to postconf the needed settings for working with OpenDKIM
postconf -e "smtpd_sasl_security_options = noanonymous, noplaintext"
postconf -e "smtpd_sasl_tls_security_options = noanonymous"
postconf -e "milter_default_action = accept"
postconf -e "milter_protocol = 6"
postconf -e "smtpd_milters = inet:localhost:12301"
postconf -e "non_smtpd_milters = inet:localhost:12301"
postconf -e "mailbox_command = /usr/libexec/dovecot/deliver"

# strips "Received From:" in sent emails
mv /etc/postfix/header_checks /etc/postfix/header_checks.backup
echo "/^Received: .*/ IGNORE" >/etc/postfix/header_checks
echo "/^User-Agent: .*/ IGNORE" >/etc/postfix/header_checks

# Create a login map file that ensures that if a sender wants to send a mail from a user at our local
# domain, they must be authenticated as that user
echo "/^(.*)@$(sh -c "echo $domain | sed 's/\./\\\./'")$/   \${1}" >/etc/postfix/login_maps.pcre

message "/etc/postfix/master.cf"

sed -i "/^\s*-o/d;/^\s*submission/d;/^\s*smtp/d" /etc/postfix/master.cf
echo '
smtp unix - - n - - smtp
smtp inet n - y - - smtpd
	-o content_filter=spamassassin
submission inet n - y - - smtpd
	-o syslog_name=postfix/submission
	-o smtpd_tls_security_level=encrypt
	-o smtpd_tls_auth_only=yes
	-o smtpd_enforce_tls=yes
	-o smtpd_sasl_auth_enable=yes
	-o smtpd_client_restrictions=permit_sasl_authenticated,reject
	-o smtpd_sender_restrictions=reject_sender_login_mismatch
	-o smtpd_sender_login_maps=pcre:/etc/postfix/login_maps.pcre
	-o smtpd_recipient_restrictions=permit_sasl_authenticated,reject_unauth_destination
smtps inet n - y - - smtpd
	-o syslog_name=postfix/smtps
	-o smtpd_tls_wrappermode=yes
	-o smtpd_sasl_auth_enable=yes
spamassassin unix - n n - - pipe
	user=spamd argv=/usr/bin/spamc -f -e /usr/sbin/sendmail -oi -f ${sender} ${recipient}' >>/etc/postfix/master.cf

message "/var/spool/postfix"

# postfix chroot
mkdir -p "$postfix_dir/etc" "$postfix_dir/lib" "$postfix_dir/usr/lib/zoneinfo"
test -d "/lib64" && mkdir -p "$postfix_dir/lib64"
lt="/etc/localtime"
if test ! -f $lt; then lt=/usr/lib/zoneinfo/localtime; fi
if test ! -f $lt; then lt=/usr/share/zoneinfo/localtime; fi
if test ! -f $lt; then
	echo "cannot find localtime"
	exit 1
fi
rm -f "$postfix_dir/etc/localtime"
cp -p -f $lt "/etc/services" "/etc/resolv.conf" "/etc/nsswitch.conf" "$postfix_dir/etc"
cp -p -f "/etc/host.conf" "/etc/hosts" "/etc/passwd" "$postfix_dir/etc"
ln -s -f "/etc/localtime" "$postfix_dir/usr/lib/zoneinfo"
chown root "/var/spool/postfix/etc/resolv.conf"
copy '/usr/lib/libnss_*.so*' lib
copy '/usr/lib/libresolv.so*' lib
copy '/usr/lib/libdb.so*' lib

# By default, dovecot has a bunch of configs in /etc/dovecot/conf.d/ These
# files have nice documentation if you want to read it, but it's a huge pain to
# go through them to organize.  Instead, we simply overwrite
# /etc/dovecot/dovecot.conf because it's easier to manage. You can get a backup
# of the original in /usr/share/dovecot if you want.
message "/etc/dovecot/dovecot.conf"

mv /etc/dovecot/dovecot.conf /etc/dovecot/dovecot_backup.conf
echo "# Dovecot config
# Note that in the dovecot conf, you can use:
# %u for username
# %n for the name in name@domain.tld
# %d for the domain
# %h the user's home directory

ssl = required
ssl_cert = <$certdir/fullchain.pem
ssl_key = <$certdir/privkey.pem
ssl_min_protocol = TLSv1.2
ssl_cipher_list = EECDH+ECDSA+AESGCM:EECDH+aRSA+AESGCM:EECDH+ECDSA+SHA256:EECDH+aRSA+SHA256:EECDH+ECDSA+SHA384:EECDH+ECDSA+SHA256:EECDH+aRSA+SHA384:EDH+aRSA+AESGCM:EDH+aRSA+SHA256:EDH+aRSA:EECDH:\!aNULL:\!eNULL:\!MEDIUM:\!LOW:\!3DES:\!MD5:\!EXP:\!PSK:\!SRP:\!DSS:\!RC4:\!SEED
ssl_prefer_server_ciphers = yes
ssl_dh = </etc/dovecot/dh.pem
auth_mechanisms = plain login
auth_username_format = %n
protocols = \$protocols imap #pop3

# Search for valid users in /etc/passwd
userdb {
	driver = passwd
}

# use passwd for user passwords
passdb {
	driver = passwd-file
	args = scheme=sha512-crypt username_format=%n /etc/dovecot/passwd
}

# Our mail for each user will be in ~/Mail, and the inbox will be ~/Mail/Inbox
# The LAYOUT option is also important because otherwise, the boxes will be \`.Sent\` instead of \`Sent\`.
mail_location = maildir:~/Mail:INBOX=~/Mail/Inbox:LAYOUT=fs

namespace inbox {
	inbox = yes

	mailbox Drafts {
		special_use = \\Drafts
		auto = subscribe
	}

	mailbox Junk {
		special_use = \\Junk
		auto = subscribe
		autoexpunge = 30d
	}

	mailbox Sent {
		special_use = \\Sent
		auto = subscribe
	}

	mailbox Trash {
		special_use = \\Trash
	}

	mailbox Archive {
		special_use = \\Archive
	}
}

# Here we let Postfix use Dovecot's authentication system.
service auth {
	unix_listener /var/spool/postfix/private/auth {
		mode = 0660
		user = postfix
		group = postfix
	}
}

protocol lda {
	mail_plugins = \$mail_plugins sieve
}

protocol lmtp {
	mail_plugins = \$mail_plugins sieve
}

plugin {
	sieve = ~/.dovecot.sieve
	sieve_default = /var/lib/dovecot/sieve/default.sieve
	sieve_dir = ~/.sieve
	sieve_global_dir = /var/lib/dovecot/sieve/
}" >/etc/dovecot/dovecot.conf

# If using an old version of Dovecot, remove the ssl_dl line.
case "$(dovecot --version)" in
1 | 2.1* | 2.2*) sed -i '/^ssl_dh/d' /etc/dovecot/dovecot.conf ;;
esac

mkdir -p /var/lib/dovecot/sieve
echo "require [\"fileinto\", \"mailbox\"];
if header :contains \"X-Spam-Flag\" \"YES\" {
	fileinto \"Junk\";
}" >/var/lib/dovecot/sieve/default.sieve

# generate /etc/dovecot/dh.pem
openssl dhparam -out /etc/dovecot/dh.pem 4096

# vmail user
grep -q '^vmail:' /etc/passwd || useradd -s /sbin/nologin vmail
chown -R vmail:vmail /var/lib/dovecot
sievec /var/lib/dovecot/sieve/default.sieve

message "/etc/opendkim"

# A lot of the big name email services, like Google, will automatically reject
# as spam unfamiliar and unauthenticated email addresses. As in, the server
# will flatly reject the email, not even delivering it to someone's Spam
# folder.

# OpenDKIM is a way to authenticate your email so you can send to such services
# without a problem.

# Create an OpenDKIM key in the proper place with proper permissions.
mkdir -p "/etc/opendkim/$domain"
opendkim-genkey -D "/etc/opendkim/$domain" -d "$domain" -s "$subdom"

# Generate the OpenDKIM info:
echo "$subdom._domainkey.$domain $domain:$subdom:/etc/opendkim/$domain/$subdom.private" >/etc/opendkim/keytable
echo "*@$domain $subdom._domainkey.$domain" >/etc/opendkim/signingtable
echo "127.0.0.1
10.1.0.0/16" >/etc/opendkim/trustedhosts

message "/etc/opendkim/opendkim.conf"
mv "/etc/opendkim/opendkim.conf" "/etc/opendkim/opendkim.backup.conf"
echo "BaseDirectory /run/opendkim
Syslog yes
SyslogSuccess yes
Canonicalization relaxed/simple
Domain $domain
Selector default
KeyFile /etc/opendkim/$domain/mail.private
Socket inet:12301@localhost
ReportAddress postmaster@example.com
SendReports yes
KeyTable file:/etc/opendkim/keytable
SigningTable refile:/etc/opendkim/signingtable
InternalHosts refile:/etc/opendkim/trustedhosts
UserID opendkim" >"/etc/opendkim/opendkim.conf"

# fix opendkim file permissions
chgrp -R opendkim /etc/opendkim
chmod -R g+r /etc/opendkim

message "FAIL2BAN"

# enable fail2ban security for dovecot and postfix.
echo "[postfix]
enabled = true
logpath = /var/log/messages
maxretry = 10

[postfix-sasl]
enabled = true
logpath = /var/log/messages
maxretry = 10

[sieve]
enabled = true
logpath = /var/log/messages
maxretry = 10

[dovecot]
enabled = true
logpath = /var/log/messages
maxretry = 10" >/etc/fail2ban/jail.d/mail.conf

message "SPAMASSASSIN"

# Enable SpamAssassin update cronjob.
sed -i 's/--m 5/--m 1/' /etc/init.d/spamd
echo "0 0 * * * sa-update" >>/var/spool/cron/crontabs/root

message "DMARC USER"

useradd -m -G mail -s /sbin/nologin dmarc

# cleanup dmarc daily
# echo "0 0 * * * find /home/dmarc/Mail -type f -mtime +30 -name '*.mail*' -delete" >>/var/spool/cron/crontabs/root

message "MAIL USER"

useradd -m -G mail "$user_name"
echo "${BOLD}${GREEN}Enter password for user ${user_name}${RESET}"
passwd "$user_name"

# generate dovecot passdb password for user
echo "${BOLD}${GREEN}Enter the password for user ${user_name} ${RED}again${RESET}"
password=$(doveadm pw -s sha512-crypt)
echo "${user_name}:${password}" >/etc/dovecot/passwd

# start services
for service in spamd opendkim dovecot postfix fail2ban; do
	rc-service "$service" restart
	rc-update add "$service" default
done

# dns entries
pval="$(tr -d '\n' <"/etc/opendkim/$domain/$subdom.txt" | sed "s/k=rsa.* \"p=/k=rsa; p=/;s/\"\s*\"//;s/\"\s*).*//" | grep -o 'p=.*')"
dkimentry="$subdom._domainkey.$domain TXT v=DKIM1; k=rsa; $pval"
dmarcentry="_dmarc.$domain TXT v=DMARC1; p=reject; rua=mailto:dmarc@$domain; fo=1"
spfentry="$domain TXT v=spf1 mx a:$maildomain -all"
mxentry="$domain MX 10 $maildomain 300"

# generate dns_entries file
echo "NOTE: Elements in the entries might appear in a different order in your registrar's DNS settings.

$dkimentry

$dmarcentry

$spfentry

$mxentry" >"$HOME/dns_entries"

echo "${BOLD}${GREEN}FINAL WORDS${RESET}"

echo "${BLUE}Add these three records to your DNS TXT records on either your registrar's site or your DNS server:${GREEN}

$dkimentry

$dmarcentry

$spfentry

$mxentry

${YELLOW}NOTE: You may need to omit the '.$domain' portion at the beginning if inputting them in a registrar's web interface.

${BLUE}Also, these are now saved to ${GREEN}~/dns_entries${BLUE} in case you want them in a file.\n$RESET"
