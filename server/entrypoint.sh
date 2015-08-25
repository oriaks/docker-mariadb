#!/bin/sh
#
#  Copyright (C) 2015 Michael Richard <michael.richard@oriaks.com>
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

if [ -n "${DEBUG}" ]; then
  set -x
fi

export DEBIAN_FRONTEND='noninteractive'
export TERM='linux'

_install () {
  [ -f /usr/sbin/mysqld ] && return

  apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 0xcbcb082a1bb943db
  cat > /etc/apt/sources.list.d/mariadb.list <<- EOF
	deb http://nyc2.mirrors.digitalocean.com/mariadb/repo/10.0/debian jessie main
EOF

  apt-get update -q
  apt-get install -y mariadb-client mariadb-galera-server pwgen

  sed -ir -f- /etc/mysql/my.cnf <<- EOF
	s|bind-address.*$|bind-address = 0.0.0.0|;
EOF

  rm -rf /var/lib/mysql/*

  return
}

_init () {
  if [ ! -f /var/lib/mysql/ibdata1 ]; then
    install -o mysql -g mysql -m 700 -d /var/lib/mysql
    mysql_install_db --datadir=/var/lib/mysql
  fi

  [ -z "${MYSQL_ROOT_PASSWORD}" -a ! -f /root/.my.cnf ] && MYSQL_ROOT_PASSWORD=`pwgen 32 1`

  if [ -n "${MYSQL_ROOT_PASSWORD}" ]; then
    MYSQLD_OPTS='--init-file=/tmp/mysql_root.sql'

    cat > /tmp/mysql_root.sql <<- EOF
	DELETE FROM mysql.user where user='root';
	FLUSH PRIVILEGES;
	CREATE USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
	GRANT ALL ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
	FLUSH PRIVILEGES;
EOF

    install -o root -p root -m 600 /dev/null /root/.my.cnf
    cat > /root/.my.cnf <<- EOF
	[client]
	host     = localhost
	password = ${MYSQL_ROOT_PASSWORD}
	user     = root
EOF
  fi

  exec /usr/bin/mysqld_safe ${MYSQLD_OPTS}

  return
}

_db_create () {
  local _DB="$1"
  [ -z "${_DB}" ] && return 1 || shift
  _db_exists "${_DB}" && return 1

  local _USER="$1"
  [ -z "${_USER}" ] && _USER="${_DB}" || shift
  _db_user_exists "${_USER}" && return 1

  local _PASSWORD="$1"
  [ -z "${_PASSWORD}" ] && _PASSWORD=`pwgen 12 1` || shift

  mysql <<- EOF
	CREATE DATABASE ${_DB};
	CREATE USER '${_USER}'@'%';
	SET PASSWORD FOR '${_USER}'@'%' = PASSWORD('${_PASSWORD}');
	GRANT ALL PRIVILEGES ON ${_DB}.* TO '${_USER}'@'%';
	FLUSH PRIVILEGES;
EOF

  echo "db: ${_DB}, user: ${_USER}, password: ${_PASSWORD}"

  return 0
}

_db_edit () {
  local _DB="$1"
  [ -z "${_DB}" ] && return 1 || shift
  _db_exists "${_DB}" || return 1

  mysql "${_DB}"

  return 0
}

_db_exists () {
  local _DB="$1"
  [ -z "${_DB}" ] && return 1 || shift
  [ `mysql -sN -e "SELECT COUNT(SCHEMA_NAME) FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='${_DB}'"` -ge 1 ] || return 1

  return 0
}

_db_list () {
  local _DB

  for _DB in `mysql -Bse 'show databases;' | sort`; do
    [ "${_DB}" = 'information_schema' ] && continue 
    [ "${_DB}" = 'mysql' ] && continue
    [ "${_DB}" = 'performance_schema' ] && continue

    printf "${_DB}\n"
  done
}

_db_user_exists () {
  local _USER="$1"
  [ -z "${_USER}" ] && return 1 || shift
  [ `mysql -sN -e "SELECT COUNT(*) FROM mysql.user WHERE user='${_USER}'"` -ge 1 ] || return 1

  return 0
}

case "$1" in
  "install")
    _$*
    ;;
  "init")
    _$*
    ;;
  "")
    /usr/bin/clish
    ;;
  _*)
    $*
    ;;
  *)
    /usr/bin/clish -c "$*"
    ;;
esac
