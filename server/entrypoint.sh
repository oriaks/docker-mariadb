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

#set -x

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

_manage () {
  _CMD="$1"
  [ -n "${_CMD}" ] && shift

  case "${_CMD}" in
    "db")
      _manage_db $*
      ;;
    *)
      _usage
      ;;
  esac

  return 0
}

_manage_db () {
  _CMD="$1"
  [ -n "${_CMD}" ] && shift

  case "${_CMD}" in
    "create")
      _manage_db_create $*
      ;;
    "edit")
      _manage_db_edit $*
      ;;
    *)
      _usage
      ;;
  esac

  return 0
}

_manage_db_create () {
  _DB="$1"
  [ -z "${_DB}" ] && return 1 || shift
  [ `mysql -sN -e "SELECT COUNT(SCHEMA_NAME) FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='${_DB}'"` -ge 1 ] && return 1

  _USER="$1"
  [ -z "${_USER}" ] && _USER="${_DB}" || shift
  [ `mysql -sN -e "SELECT COUNT(*) FROM mysql.user WHERE user='${_USER}'"` -ge 1 ] && return 1

  _PASSWORD="$1"
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

_manage_db_edit () {
  _DB="$1"
  [ -z "${_DB}" ] && return 1 || shift
  [ `mysql -sN -e "SELECT COUNT(SCHEMA_NAME) FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='${_DB}'"` -ge 1 ] || return 1

  mysql "${_DB}"

  return 0
}

_shell () {
  exec /usr/bin/clish

  return
}

_usage () {
  cat <<- EOF
	Usage: $0 install
	       $0 init
	       $0 manage db create <database_name> [ <user_name> [ <password> ]]
	       $0 manage db edit <database_name>
	       $0 shell
EOF

  return
}

_CMD="$1"
[ -n "${_CMD}" ] && shift

case "${_CMD}" in
  "install")
    _install $*
    ;;
  "init")
    _init $*
    ;;
  "manage")
    _manage $*
    ;;
  "shell")
    _shell $*
    ;;
  *)
    _usage
    ;;
esac
