FROM ubuntu:latest
MAINTAINER Frank DiRocco <frank2@diroccos.com>

EXPOSE 80

ENV ZM_DB_HOST 127.0.0.1
ENV ZM_DB_NAME zm
ENV ZM_DB_USER zmuser
ENV ZM_TMP_PATH /var/tmp/zm
ENV ZM_SOCK_PATH /var/tmp/zm
ENV ZM_LOGS_PATH /var/log/zoneminder

RUN apt-get update \
  && apt-get install -y \
    software-properties-common \
    apt-utils \
    pwgen \
  && export DEBIAN_FRONTEND=noninteractive \
  && echo "mariadb-server mariadb-server/root_password password mysqltmppass" >> /tmp/debconf-selections \
  && echo "mariadb-server mariadb-server/root_password_again password mysqltmppass" >> /tmp/debconf-selections \
  && debconf-set-selections /tmp/debconf-selections \
  && add-apt-repository ppa:iconnor/zoneminder \
  && apt-get update \
  && apt-get upgrade -y \
  && apt-get dist-upgrade -y \
  && apt-get install -y \
    sudo \
    supervisor \
    zoneminder \
    apache2

ADD . /opt/src

WORKDIR /opt/src

ADD docker-entrypoint.sh /docker-entrypoint.sh

RUN chmod +x /docker-entrypoint.sh \
  && mkdir -p /tmp/zm \
  && mkdir -p /var/run/zm \
  && mkdir -p /var/run/mysqld \
  && mkdir -p /var/log/zoneminder \
  && chown mysql:mysql /var/run/mysqld \
  && cp -f /etc/mysql/mysql.conf.d/mysqld.cnf /etc/mysql/my.cnf \
  && ln -sf /opt/src/config/supervisord.conf /etc/supervisor/supervisord.conf \
  && ln -sf /opt/src/config/phpdate.ini /etc/php/7.0/apache2/conf.d/25-phpdate.ini

VOLUME ["/var/lib/mysql", "/usr/share/zoneminder"]

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["supervisord"]
