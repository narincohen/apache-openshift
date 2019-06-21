FROM debian:stretch
ARG DEBIAN_VERSION=stretch
ARG APACHE_OPENIDC_VERSION=2.3.11
ARG USER_ID=2000
ARG TZ=UTC
ARG CA_HOSTS_LIST
RUN env
# System - Update embded package
RUN apt-get -y update \
    && apt-get -y upgrade \
    && apt-get install -y --no-install-recommends ca-certificates netcat curl apache2
# System - Set default timezone
ENV TZ ${TZ}
# Apache - configuration
COPY apache2/conf-available/ /etc/apache2/conf-available/
# Apache - mod-auth-openidc (https://github.com/zmartzone/mod_auth_openidc/)
RUN apt-get install -y --no-install-recommends libapache2-mod-auth-openidc
RUN curl -sSL https://github.com/zmartzone/mod_auth_openidc/releases/download/v${APACHE_OPENIDC_VERSION}/libapache2-mod-auth-openidc_${APACHE_OPENIDC_VERSION}-1.${DEBIAN_VERSION}+1_amd64.deb > libapache2-mod-auth-openidc.deb \
    && dpkg -i libapache2-mod-auth-openidc.deb \
    && rm -f libapache2-mod-auth-openidc.deb
# Apache - disable Etag
RUN a2enconf etag
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
# Apache - Logging
RUN sed -i -e 's/vhost_combined/combined/g' -e 's/other_vhosts_access/access/g' /etc/apache2/conf-available/other-vhosts-access-log.conf
# Apache - Syslog Log
ENV APACHE_SYSLOG_PORT 514
ENV APACHE_SYSLOG_PROGNAME httpd
# Apache- Prepare to be run as non root user
RUN mkdir -p /var/lock/apache2 /var/run/apache2 \
    && chgrp -R 0 /run /var/run/apache2 /var/lock/apache2 /var/log/apache2 \
    && chmod -R g=u /etc/passwd /run /var/run/apache2 /var/lock/apache2 /var/log/apache2
RUN rm -f /var/log/apache2/*.log \
    && ln -s /proc/self/fd/2 /var/log/apache2/error.log \
    && ln -s /proc/self/fd/1 /var/log/apache2/access.log
RUN sed -i -e 's/80/8080/g' -e 's/443/8443/g' /etc/apache2/ports.conf
EXPOSE 8080 8443
# System - Clean apt
RUN apt-get autoremove -y
COPY docker-bin/ /docker-bin/
RUN chmod a+rx /docker-bin/*.sh \
    && /docker-bin/docker-build.sh
USER ${USER_ID}
ENTRYPOINT ["/docker-bin/docker-entrypoint.sh"]
CMD ["apache2ctl", "-DFOREGROUND"]