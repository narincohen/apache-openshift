#!/bin/bash

if [ $(id -u) -ne 0 ]; then
    echo "Script should be run as root during buildtime."
    exit 1
else
    echo "Running as root that's cool :)"
fi

# System - set exec on scripts in /docker-bin/
echo "Set exec mode on '/docker-bin/*.sh'"
chmod a+rx /docker-bin/*.sh 

# System - set the proper timezone
if [ -n "${TZ}" ]; then
	ln -snf "/usr/share/zoneinfo/$TZ" "/etc/localtime"
	echo "$TZ" > /etc/timezone
fi

# System - Add extra ca-certificate to system certificates
if [ -n "${CA_HOSTS_LIST}" ]; then
    for hostAndPort in ${CA_HOSTS_LIST}; do
        echo "Adding ca-certificate of ${hostAndPort}"
        openssl s_client -connect ${hostAndPort} -showcerts < /dev/null | awk '/BEGIN/,/END/{ if(/BEGIN/){a++}; out="/usr/local/share/ca-certificates/'${hostAndPort}'"a".crt"; print >out}'
    done
    update-ca-certificates
fi

tz=$(ls -l "/etc/localtime" | awk '{print $NF}' | sed -e 's#/usr/share/zoneinfo/##g')
echo "TZ: ${TZ:-default} (effective ${tz})"

# Cron - Merge all files in /etc/cron.d into /etc/crontab
if [ -d "/etc/cron.d" ]; then
	# Remove the user name and merge into one file
    echo "Merging cron in '/etc/cron.d' into '/etc/crontab'"
	sed -r 's/(\s+)?\S+//6' /etc/cron.d/* > /etc/crontab
fi

if [ -f "/etc/crontab" ]; then
    echo "Set mode g=rw on '/etc/crontab'"
    chmod 664 /etc/crontab
fi

# Apache - Fix upstream link error
if [ -d /var/www/html ]; then
    rm -rf /var/www/html
    ln -s ${APP_DIR}/web/ /var/www/html
fi

# Apache - fix cache directory
if [ -d /var/cache/apache2 ]; then
    chgrp -R 0 /var/cache/apache2
    chmod -R g=u /var/cache/apache2
fi