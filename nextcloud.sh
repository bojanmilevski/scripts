#!/bin/sh

# https://wiki.alpinelinux.org/wiki/Nextcloud

domain=""

[ -z "$domain" ] && echo "Specify domain name!" && exit 1

apk add nextcloud-sqlite nextcloud-initscript nextcloud-files_sharing nginx certbot php81-fpm

certbot certonly --standalone -d "$domain" -d "www.$domain"

echo 'server {
	listen 80;
	listen [::]:80;
	return 301 https://$host$request_uri;' >"/etc/nginx/http.d/cloud.conf"

echo "	server_name $domain www.$domain
}
" >>"/etc/nginx/http.d/cloud.conf"

echo 'server {
	listen 443 ssl http2;
	listen [::]:443 ssl;
' >>"/etc/nginx/http.d/cloud.conf"

echo "	server_name $domain www.$domain" >>"/etc/nginx/http.d/cloud.conf"

echo '
	root /usr/share/webapps/nextcloud;
	index index.php index.html index.htm;
	disable_symlinks off;
' >>"/etc/nginx/http.d/cloud.conf"

echo "	ssl_certificate /etc/letsencrypt/live/$domain/
	ssl_certificate_key /etc/letsencrypt/live/$domain/" >>"/etc/nginx/http.d/cloud.conf"

echo '
	ssl_session_timeout 5m;

	#Enable Perfect Forward Secrecy and ciphers without known vulnerabilities
	#Beware! It breaks compatibility with older OS and browsers (e.g. Windows XP, Android 2.x, etc.)
	ssl_ciphers ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA;
	ssl_prefer_server_ciphers on;

	location / {
		try_files $uri $uri/ /index.html;
	}

	# pass the PHP scripts to FastCGI server listening on 127.0.0.1:9000
	location ~ [^/]\.php(/|$) {
		fastcgi_split_path_info ^(.+?\.php)(/.*)$;

		if (!-f $document_root$fastcgi_script_name) {
				return 404;
		}

		#fastcgi_pass 127.0.0.1:9000;
		#fastcgi_pass unix:/run/php-fpm/socket;
		fastcgi_pass unix:/run/nextcloud/fastcgi.sock; # From the nextcloud-initscript package
		fastcgi_index index.php;
		include fastcgi.conf;
	}

	# Help pass nextclouds configuration checks after install:
	# Per https://docs.nextcloud.com/server/22/admin_manual/issues/general_troubleshooting.html#service-discovery
	location ^~ /.well-known/carddav { return 301 /remote.php/dav/; }
	location ^~ /.well-known/caldav { return 301 /remote.php/dav/; }
	location ^~ /.well-known/webfinger { return 301 /index.php/.well-known/webfinger; }
	location ^~ /.well-known/nodeinfo { return 301 /index.php/.well-known/nodeinfo; }
}' >>"/etc/nginx/http.d/cloud.conf"

sed -i "s/client_max_body_size 1m;/client_max_body_size 0;" "/etc/nginx/nginx.conf"

echo "php_admin_value[post_max_size] = 513M
php_admin_value[upload_max_filesize] = 513M" >>"/etc/php81/php-fpm.d/nextcloud.conf"

rc-update add nginx default
rc-update add nextcloud default
service nginx restart
service nextcloud restart
