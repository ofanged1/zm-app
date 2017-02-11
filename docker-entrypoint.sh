#!/bin/bash

# Capture default or variables
SHM=${SHM:-512M}
LOCALHOSTS=( "127.0.0.1" "localhost" )
ZM_DB_HOST=${ZM_DB_HOST:-"127.0.0.1"}
ZM_DB_NAME=${ZM_DB_NAME:-"zm"}
ZM_DB_USER=${ZM_DB_USER:-"zmuser"}
ZM_DB_PASS=${ZM_DB_PASS:-$(pwgen -s 12 1)}
ZM_ADMIN_USER=${ZM_ADMIN_USER:-"admin"}
ZM_ADMIN_PASS=${ZM_ADMIN_PASS:-$(pwgen -s 12 1)}
ZM_TMP_PATH=${ZM_TMP_PATH:-"/var/tmp/zm"}
ZM_SOCK_PATH=${ZM_SOCK_PATH:-"/var/tmp/zm"}
ZM_LOGS_PATH=${ZM_LOGS_PATH:-"/var/log/zoneminder"}

# Test if docker container has privileged mode enabled
Privileged() {

  PRIVILEGED=1
  if [ $(ip link add dummy0 type dummy >/dev/null; echo $?) -eq 0 ]; then
    PRIVILEGED=0
    # clean the dummy0 link
    ip link delete dummy0 >/dev/null
  fi
  return $PRIVILEGED

}

# Start MySQL in safe mode and wait for it to complete
StartMySQL () {

  /usr/bin/mysqld_safe > /dev/null 2>&1 &
  # Time out in 1 minute
  LOOP_LIMIT=60
  for (( i=0 ; ; i++ )); do
    if [ ${i} -eq ${LOOP_LIMIT} ]; then
      echo "Time out. Error log is shown as below:"
      tail -n 100 ${LOG}
      exit 1
    fi
    echo "=> Waiting for confirmation of MySQL service startup, trying ${i}/${LOOP_LIMIT} ..."
    sleep 1
    mysql -uroot -e "status" > /dev/null 2>&1 && break
  done

}

# Stop MySQL gracefully and wait for it to complete
StopMySQL() {

  kill $(cat /var/run/mysqld/mysqld.pid)
  # Time out in 1 minute
  LOOP_LIMIT=60
  for (( i=0 ; ; i++ )); do
      if [ ${i} -eq ${LOOP_LIMIT} ]; then
          echo "Time out. Error log is shown as below:"
          tail -n 100 ${LOG}
          exit 1
      fi
      echo "=> Waiting for confirmation of MySQL service startup, trying ${i}/${LOOP_LIMIT} ..."
      sleep 1
      mysql -uroot -e "status" > /dev/null 2>&1 || break
  done

}

# Secury MySQL removing empty password, create app db and permissions
# add /root/.my.cnf to store credentials
CreateMySQLUser() {

  echo -n "=> Creating MySQL user ${ZM_DB_USER} with ${#ZM_DB_PASS} character password..."

  mysql -uroot -e "UPDATE mysql.user SET authentication_string=Password('$ZM_DB_PASS') where authentication_string='';
  CREATE DATABASE IF NOT EXISTS ${ZM_DB_NAME};
  CREATE USER '${ZM_DB_USER}'@'127.0.0.1' IDENTIFIED BY '$ZM_DB_PASS';
  GRANT SELECT,INSERT,UPDATE,DELETE,CREATE,ALTER,INDEX,LOCK TABLES ON ${ZM_DB_NAME}.* TO '${ZM_DB_USER}'@'127.0.0.1';
  FLUSH PRIVILEGES;"

  # Leave a /root/.my.cnf so we can get back into the db
  echo "[client]" >> /root/.my.cnf
  echo "user=root" >> /root/.my.cnf
  echo "password=${ZM_DB_PASS}" >> /root/.my.cnf

  echo " Done"

}

# Populate the zoneminder database with chosen admin password
SeedZoneMinder() {

  echo "=> Seeding the ZoneMinder Initial Database... "
  echo -n "=> Creating ZoneMonitor user ${ZM_ADMIN_USER} with ${ZM_ADMIN_PASS} password..."

  cp /usr/share/zoneminder/db/zm_create.sql /tmp/zm_create.sql
  sed -i "s/'admin',password('admin')/'${ZM_ADMIN_USER}',password('${ZM_ADMIN_PASS}')/g" /tmp/zm_create.sql
  mysql -uroot ${ZM_DB_NAME} < /tmp/zm_create.sql
  rm -f /tmp/zm_create.sql

  echo "Done"

}

# Configure Apache, MySQL and Zoneminder itself
ConfigureZoneMinder() {

  echo "=> Configuring Zoneminder..."

  # Enable Apache Sites & Modules
  a2dissite 000-default
  a2disconf javascript-common
  a2disconf other-vhosts-access-log
  a2disconf serve-cgi-bin

  #a2ensite zoneminder
  a2enconf zoneminder
  a2enmod mpm_prefork
  a2enmod rewrite
  a2enmod php7.0
  a2enmod cgi

  # Ensure the connection string is updated
  sed -i "s/ZM_DB_HOST=.*/ZM_DB_HOST=${ZM_DB_HOST}/" /etc/zm/zm.conf
  sed -i "s/ZM_DB_NAME=.*/ZM_DB_NAME=${ZM_DB_NAME}/" /etc/zm/zm.conf
  sed -i "s/ZM_DB_USER=.*/ZM_DB_USER=${ZM_DB_USER}/" /etc/zm/zm.conf
  sed -i "s/ZM_DB_PASS=.*/ZM_DB_PASS=${ZM_DB_PASS}/" /etc/zm/zm.conf

  mv /etc/zm/zm.conf /usr/share/zoneminder/
  ln -s /usr/share/zoneminder/zm.conf /etc/zm/zm.conf

  # set permissions on zm config
  chown root:www-data /etc/zm/zm.conf /usr/share/zoneminder/zm.conf
  chmod 740 /etc/zm/zm.conf /usr/share/zoneminder/zm.conf
  chown -R www-data:www-data \
    /var/log/zoneminder \
    /usr/share/zoneminder \
    /var/cache/zoneminder \
    /var/run/zm \
    /tmp/zm

  # MySQL 5.7 fixes
  sed -i "/sql_mode.*/d" /etc/mysql/my.cnf
  echo "sql_mode = NO_ENGINE_SUBSTITUTION" >> /etc/mysql/my.cnf
  sed -i "s/#max_connections.*/max_connections        = 40/" /etc/mysql/my.cnf
  sed -i "s/tmpdir.*/tmpdir = \/dev\/shm/" /etc/mysql/my.cnf

}

# Main Execution

# Only perform local db setup if the db host is in localhosts array
if [[ " ${LOCALHOSTS[@]} " =~ " ${ZM_DB_HOST} " ]]; then

  # Create, secure, seed the database if it's not already done
  if [ ! -d "/var/lib/mysql/${ZM_DB_NAME}" ]; then
    StartMySQL
    CreateMySQLUser
    SeedZoneMinder
    StopMySQL
  fi

else

  echo "=! Remote database connection string found"
  echo "=! Ensure you imported the zoneminder DB schema!"

fi # end of local database setup

# Run configuration when not been run
if [ ! -f /usr/share/zoneminder/.zm.configured ]; then

  ConfigureZoneMinder
  touch /usr/share/zoneminder/.zm.configured

fi

# Remount the tmpfs if we are running in privileged mode, otherwise pray
if [ $(Privileged;echo $?) -eq 0 ]; then

  echo -n "=> Remounting tmpfs with 512M... "
  umount /dev/shm
  mount -t tmpfs -o rw,nosuid,nodev,noexec,relatime,size=${SHM} tmpfs /dev/shm
  echo "Done"

else

  echo "=> Skipping tmpfs remount at ${SHM} due to lack of permissions, use \"--privileged\" option when running container"

fi

# Execute CMD passed to entrypoint
exec "$@"
