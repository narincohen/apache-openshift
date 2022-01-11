FROM debian:bullseye@sha256:2906804d2a64e8a13a434a1a127fe3f6a28bf7cf3696be4223b06276f32f1f2d
ARG DEBIAN_VERSION=bullseye
ARG APACHE_OPENIDC_VERSION=2.4.10
ARG USER_ID=2000
ARG TZ=UTC
ARG CA_HOSTS_LIST
# System - Update embded package
# hadolint ignore=DL3008
RUN apt-get -y update \
    && apt-get install -y --no-install-recommends ca-certificates netcat curl apache2 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
# System - Set default timezone
ENV TZ=${TZ}
# Apache - Disable not necessary module
# hadolint ignore=DL3008,DL3059
RUN a2dismod -f access_compat auth_basic authn_file autoindex authn_file authz_user env filter reqtimeout setenvif \
    # Apache - mod-auth-openidc (https://github.com/zmartzone/mod_auth_openidc/)
    && apt-get -y update \
    && apt-get install -y --no-install-recommends libapache2-mod-auth-openidc \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && if [ "${DEBIAN_VERSION}" != "bullseye" ]; then \
        curl -sSL "https://github.com/zmartzone/mod_auth_openidc/releases/download/v${APACHE_OPENIDC_VERSION}/libapache2-mod-auth-openidc_${APACHE_OPENIDC_VERSION}-1.${DEBIAN_VERSION}+1_amd64.deb" > libapache2-mod-auth-openidc.deb \
            && dpkg -i libapache2-mod-auth-openidc.deb \
            && rm -f libapache2-mod-auth-openidc.deb; \
    fi \
    && a2dismod auth_openidc
COPY image-files/ /
# Apache - disable Etag
RUN a2enconf etag \
    # Apache - Disable useless configuration
    && a2disconf serve-cgi-bin \
    # Apache - remoteip module
    && a2enmod remoteip \
    && sed -i 's/%h/%a/g' /etc/apache2/apache2.conf
ENV APACHE_REMOTE_IP_HEADER=X-Forwarded-For
ENV APACHE_REMOTE_IP_TRUSTED_PROXY="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16"
ENV APACHE_REMOTE_IP_INTERNAL_PROXY="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16"
RUN a2enconf remoteip
# Apache - Hide version
RUN sed -i -e 's/^ServerTokens OS$/ServerTokens Prod/g' \
        -e 's/^ServerSignature On$/ServerSignature Off/g' \
        /etc/apache2/conf-available/security.conf
# Apache - Avoid warning at startup
ENV APACHE_SERVER_NAME=__default__
RUN a2enconf servername \
    # Apache - Logging
    && sed -i -e 's/vhost_combined/combined/g' -e 's/other_vhosts_access/access/g' /etc/apache2/conf-available/other-vhosts-access-log.conf
# Apache - enable X-Content-Type-Options
RUN a2enmod headers \
    && sed -i -e '/X-Content-Type-Options/s/^#//g' /etc/apache2/conf-available/security.conf
# Apache - Syslog Log
ENV APACHE_SYSLOG_PORT=514
ENV APACHE_SYSLOG_PROGNAME=httpd
RUN rm -f /var/log/apache2/*.log \
    && ln -s /proc/self/fd/2 /var/log/apache2/error.log \
    && ln -s /proc/self/fd/1 /var/log/apache2/access.log
EXPOSE 8080 8443
RUN sed -i -e 's/80/8080/g' -e 's/443/8443/g' /etc/apache2/ports.conf \
    # Apache- Prepare to be run as non root user
    && mkdir -p /var/lock/apache2 /var/run/apache2 \
    && chgrp -R 0 /etc/apache2/mods-* \
        /etc/apache2/sites-* \
        /run /var/lib/apache2 \
        /var/run/apache2 \
        /var/lock/apache2 \
        /var/log/apache2 \
    && chmod -R g=u /etc/passwd \
        /etc/apache2/mods-* \
        /etc/apache2/sites-* \
        /run \
        /var/lib/apache2 \
        /var/run/apache2 \
        /var/lock/apache2 \
        /var/log/apache2 \
    # Apache - Display information (version, module)
    && a2query -v \
    && a2query -M \
    && a2query -m \
    && chmod a+rx /docker-bin/*.sh \
    && /docker-bin/docker-build.sh
USER ${USER_ID}
ENTRYPOINT ["/docker-bin/docker-entrypoint.sh"]
CMD ["apache2ctl", "-DFOREGROUND"]