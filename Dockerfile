FROM debian:stretch

ARG USER_ID=2000
ARG CA_HOSTS_LIST

# System - Update embded package
RUN apt-get -y update \
    && apt-get -y upgrade \
    && apt-get install -y netcat curl libapache2-mod-auth-openidc

# System - Set default timezone
ENV TZ ${TZ}

# System - Add letsencrypt.org ca-certificate to system certificate (https://letsencrypt.org/docs/staging-environment/)
RUN curl --connect-timeout 3 -fsS https://letsencrypt.org/certs/fakelerootx1.pem -o /usr/local/share/ca-certificates/fakelerootx1.crt \
    && update-ca-certificates

# Apache
RUN apt-get install -y --no-install-recommends curl apache2 ca-certificates
RUN a2enmod auth_openidc rewrite remoteip

# Apache - configuration
COPY apache2/conf-available/ /etc/apache2/conf-available/

# Apache - Disable useless configuration
RUN a2disconf serve-cgi-bin

# Apache - remoteip module
RUN a2enmod remoteip
RUN sed -i 's/%h/%a/g' /etc/apache2/apache2.conf
ENV APACHE_REMOTE_IP_HEADER X-Forwarded-For
ENV APACHE_REMOTE_IP_TRUSTED_PROXY 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16
ENV APACHE_REMOTE_IP_INTERNAL_PROXY 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16
RUN a2enconf remoteip

# Apache - Hide version 
RUN sed -i 's/^ServerTokens OS$/ServerTokens Prod/g' /etc/apache2/conf-available/security.conf

# Apache - Avoid warning at startup
ENV APACHE_SERVER_NAME __default__
RUN a2enconf servername

# Apache - Update log format
RUN sed -i -e 's/vhost_combined/combined/g' -e 's/other_vhosts_access/access/g' /etc/apache2/conf-available/other-vhosts-access-log.conf

# Apache - Syslog Log
ENV APACHE_SYSLOG_PORT 514
ENV APACHE_SYSLOG_PROGNAME httpd

# Apache- Prepare to be run as non root user
RUN mkdir /var/lock/apache2 /var/www/html/aaio /var/www/html/archives \
    /var/www/html/at /var/www/html/nt /var/www/html/puppet \
    /var/www/html/puppet-win /var/www/html/retd /var/www/html/ris-rezo \
    /var/www/html/securite /var/www/html/supervision /var/www/html/unix \
    && chgrp -R 0 /run /var/lock/apache2 /var/log/apache2 /var/www/html \
    && chmod -R g=u /etc/passwd /run /var/lock/apache2 /var/log/apache2 /var/www/html
RUN rm -f /var/log/apache2/*.log \
    && ln -s /proc/self/fd/2 /var/log/apache2/error.log \
    && ln -s /proc/self/fd/1 /var/log/apache2/access.log
RUN sed -i -e 's/80/8080/g' -e 's/443/8443/g' /etc/apache2/ports.conf
EXPOSE 8080 8443

# Apache - default virtualhost configuration
COPY apache2/sites-available/ /etc/apache2/sites-available/

# System - Clean apt
RUN apt-get autoremove -y
COPY docker-bin/ /docker-bin/
RUN chmod a+rx /docker-bin/*.sh \
    && /docker-bin/docker-build.sh

USER ${USER_ID}

ENTRYPOINT ["/docker-bin/docker-entrypoint.sh"]

CMD ["apache2ctl", "-DFOREGROUND"]