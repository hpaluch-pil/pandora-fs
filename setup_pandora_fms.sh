#!/bin/bash
# setup_pandora_fms.sh - setup Pandora FMS on Rocky Linux 8
# cloned from: github.com/hpaluch/osfs
# based on: https://pandorafms.com/manual/!current/en/documentation/pandorafms/technical_annexes/31_pfms_install_latest_rocky_linux

set -euo pipefail

# feel free to add your favorite packages to this variable:
EXTRA_PKGS='mc git-core tmux'
PFMS_VERXXX=777
PFMS_VERFULL=7.0NG.777

HOST=`hostname -f`
HOST_IP=`hostname -i`
OVERLAY_INTERFACE_IP_ADDRESS=$HOST_IP

# change working directory to this script location
cd $(dirname $0)
# get full absolute path of this directory (we will later use it to apply Nova Bridge name patch)
WD=`pwd`

echo "HOST='$HOST' HOST_IP='$HOST_IP'"

ENABLE_TRACE="set -x"
#ENABLE_TRACE=true
CFG_BASE=$HOME/.config/pandorafs
CFG_STAGE_DIR=$CFG_BASE/stages
CFG_SEC_DIR=$CFG_BASE/secrets
MYSQL_ROOT_PWD_FILE=$CFG_SEC_DIR/mysql_root_pwd.txt

# error and exit
errx ()
{
	echo "ERROR: $*" >&2
	exit 1
}

# warn but not exit
warn ()
{
	echo "WARNING: $*" >&2
}


setup_mysql_db ()
{
	# arguments: DB_NAME USER_NAME
	local db=$1
	local user=$2
	local db_pwd_file=$CFG_SEC_DIR/mysql_${user}_pwd.txt
	echo A`openssl rand -hex 10`'C%=^_' > $db_pwd_file
	local db_pwd=`cat $db_pwd_file | tr -d '\r\n'`
mysql -u root -p`cat $MYSQL_ROOT_PWD_FILE`  <<EOF
DROP USER IF EXISTS $user;
DROP DATABASE IF EXISTS $db;
CREATE DATABASE $db;
CREATE USER '$user'@'%' IDENTIFIED WITH 'caching_sha2_password' BY '$db_pwd';
GRANT ALL PRIVILEGES ON $db.* TO '$user'@'%';
FLUSH PRIVILEGES;
EOF
}

extract_db_pwd ()
{
	local user=$1
	local db_pwd_file=$CFG_SEC_DIR/mysql_${user}_pwd.txt
	cat $db_pwd_file | tr -d '\r\n'
}

# check that we are on right distro

# must be: PLATFORM_ID="platform:el8"
# always run in sub-shell to avoid cluttering main environment
( source /etc/os-release && [[ $PLATFORM_ID =~ el8$  ]] || errx "Unexpected PLATFORM_ID='$PLATFORM_ID'" )

# check that we are on rocky-linux (warning)
( source /etc/os-release && [ "$ID" = rocky  ] || warn "Unexpected ID='$ID', only 'rocky' supported" )

for i in $CFG_BASE $CFG_STAGE_DIR $CFG_SEC_DIR
do
	[ -d "$i" ] || mkdir -vp "$i"
done

set -x

STAGE=$CFG_STAGE_DIR/001basepkg
[ -z "$EXTRA_PKGS" -o -f $STAGE ] || {
	sudo dnf install -y $EXTRA_PKGS
	touch $STAGE
}

STAGE=$CFG_STAGE_DIR/002crudini
[ -f $STAGE ] || {
	# FIXME - proper stable link
	# but we don't want to mess system with globally enabled EPEL 8
	rpm -q crudini || sudo dnf install -y https://dl.fedoraproject.org/pub/epel/8/Everything/x86_64/Packages/c/crudini-0.9.3-1.el8.noarch.rpm
	touch $STAGE
}

set -x
STAGE=$CFG_STAGE_DIR/003dnf-keep-cache
[ -f $STAGE ] || {
	f=/etc/dnf/dnf.conf
	sudo crudini --set $f main keepcache True
	touch $STAGE
}

# Now we are more or less copying: https://pandorafms.com/manual/!current/en/documentation/pandorafms/technical_annexes/31_pfms_install_latest_rocky_linux

STAGE=$CFG_STAGE_DIR/pfs02repo-settings
[ -f $STAGE ] || {
	sudo dnf install -y epel-release tar dnf-utils \
	    http://rpms.remirepo.net/enterprise/remi-release-8.rpm
	sudo dnf module reset php
	sudo dnf module install -y php:remi-8.2
	sudo dnf config-manager --set-enabled powertools

	touch $STAGE
}

STAGE=$CFG_STAGE_DIR/pfs03percona-install
[ -f $STAGE ] || {
	sudo dnf install -y https://repo.percona.com/yum/percona-release-latest.noarch.rpm
	sudo dnf module disable -y mysql
	sudo rm -rf /etc/my.cnf
	sudo percona-release setup ps80
	sudo dnf install -y percona-server-server percona-xtrabackup-80

	touch $STAGE
}

STAGE=$CFG_STAGE_DIR/pfs04wc-deps
[ -f $STAGE ] || {
	sudo dnf install -y \
    php \
    postfix \
    php-mcrypt \
    php-cli \
    php-gd \
    php-curl \
    php-session \
    php-mysqlnd \
    php-ldap \
    php-zip \
    php-zlib \
    php-fileinfo \
    php-gettext \
    php-snmp \
    php-mbstring \
    php-pecl-zip \
    php-xmlrpc \
    php-fpm \
    php-xml \
    php-yaml \
    libxslt \
    wget \
    httpd \
    mod_php \
    atk \
    avahi-libs \
    cairo \
    cups-libs \
    fribidi \
    gd \
    gdk-pixbuf2 \
    ghostscript \
    graphite2 \
    graphviz \
    gtk2 \
    harfbuzz \
    hicolor-icon-theme \
    hwdata \
    jasper-libs \
    lcms2 \
    libICE \
    libSM \
    libXaw \
    libXcomposite \
    libXcursor \
    libXdamage \
    libXext \
    libXfixes \
    libXft \
    libXi \
    libXinerama \
    libXmu \
    libXrandr \
    libXrender \
    libXt \
    libXxf86vm \
    libcroco \
    libdrm \
    libfontenc \
    libglvnd \
    libglvnd-egl \
    libglvnd-glx \
    libpciaccess \
    librsvg2 \
    libthai \
    libtool-ltdl \
    libwayland-client \
    libwayland-server \
    libxshmfence \
    mesa-libEGL \
    mesa-libGL \
    mesa-libgbm \
    mesa-libglapi \
    pango \
    pixman \
    xorg-x11-fonts-75dpi \
    xorg-x11-fonts-misc \
    poppler-data \
    mod_ssl \
    libzstd \
    openldap-clients \
    https://firefly.pandorafms.com/centos8/chromium-122.0.6261.128-1.el8.x86_64.rpm \
    https://firefly.pandorafms.com/centos8/chromium-common-122.0.6261.128-1.el8.x86_64.rpm \
    http://firefly.pandorafms.com/centos8/perl-Net-Telnet-3.04-1.el8.noarch.rpm \
    http://firefly.pandorafms.com/centos7/wmic-1.4-1.el7.x86_64.rpm

	touch $STAGE
}

STAGE=$CFG_STAGE_DIR/pfs05pfms
[ -f $STAGE ] || {
   sudo dnf install -y \
	perl vim fping perl-IO-Compress nmap sudo perl-Time-HiRes nfdump \
	net-snmp-utils 'perl(NetAddr::IP)' 'perl(Sys::Syslog)' 'perl(DBI)' \
	'perl(XML::Simple)' 'perl(Geo::IP)' 'perl(IO::Socket::INET6)' \
	'perl(XML::Twig)' expect openssh-clients java bind-utils \
	whois libnsl \
	http://firefly.pandorafms.com/centos7/xprobe2-0.3-12.2.x86_64.rpm \
	http://firefly.pandorafms.com/centos7/wmic-1.4-1.el7.x86_64.rpm \
	https://firefly.pandorafms.com/centos8/pandorawmic-1.0.0-1.x86_64.rpm

   touch $STAGE
}

# HP fix:
# missing Net::SNMP required by:
# /usr/share/pandora_server/util/plugin/wizard_snmp_module.pl and wizard_snmp_process.pl
STAGE=$CFG_STAGE_DIR/pfs05pfms-hpfix
[ -f $STAGE ] || {
	sudo dnf install -y 'perl(Net::SNMP)'
	touch $STAGE
}

STAGE=$CFG_STAGE_DIR/pfs06pfms-vmware
[ -f $STAGE ] || {
	sudo dnf install -y \
	    perl-Net-HTTP \
	    perl-libwww-perl \
	    openssl-devel \
	    perl-Crypt-CBC \
	    perl-Bytes-Random-Secure \
	    perl-Crypt-Random-Seed \
	    perl-Math-Random-ISAAC \
	    perl-JSON \
	    perl-Crypt-SSLeay \
	    http://firefly.pandorafms.com/centos8/perl-Crypt-OpenSSL-AES-0.02-1.el8.x86_64.rpm \
	    http://firefly.pandorafms.com/centos8/VMware-vSphere-Perl-SDK-6.5.0-4566394.x86_64.rpm

	touch $STAGE
}

STAGE=$CFG_STAGE_DIR/pfs07pfms-oracle
[ -f $STAGE ] || {
	sudo dnf install -y \
  https://download.oracle.com/otn_software/linux/instantclient/19800/oracle-instantclient19.8-basic-19.8.0.0.0-1.x86_64.rpm \
  https://download.oracle.com/otn_software/linux/instantclient/19800/oracle-instantclient19.8-sqlplus-19.8.0.0.0-1.x86_64.rpm

	touch $STAGE
}

STAGE=$CFG_STAGE_DIR/pfs08pfms-msodbc
[ -f $STAGE ] || {
	sudo curl https://packages.microsoft.com/config/rhel/8/prod.repo -o /etc/yum.repos.d/mssql-release.repo
	sudo dnf remove unixODBC-utf16 unixODBC-utf16-devel
	sudo env ACCEPT_EULA=Y dnf install -y msodbcsql17

	touch $STAGE
}

STAGE=$CFG_STAGE_DIR/pfs09a-pfms-disable-selinux
[ -f $STAGE ] || {
	sudo setenforce 0
	sudo sed -i -e "s/^SELINUX=.*/SELINUX=disabled/g" /etc/selinux/config
	sudo systemctl disable firewalld --now

	touch $STAGE
}

# we must use terrible trickery to reset MySQL root temporary password to permanent one...
STAGE=$CFG_STAGE_DIR/pfs09b-pfms-mysql-temp
[ -f $STAGE ] || {
	# properly RESET all environment:
	sudo systemctl stop mysqld
	# must be removed (contains temporary password)
	sudo rm -f /var/log/mysqld.log
	sudo rm -rf /var/lib/mysql
	sudo mkdir /var/lib/mysql
	sudo chown mysql:mysql /var/lib/mysql
	sudo tee /etc/my.cnf <<EO_CONFIG_TMP
[mysqld]
datadir=/var/lib/mysql
socket=/var/lib/mysql/mysql.sock
symbolic-links=0
log-error=/var/log/mysqld.log
pid-file=/var/run/mysqld/mysqld.pid
EO_CONFIG_TMP
	sudo systemctl start mysqld
	# temporary MySQL root password that must be changed to continue
	MYSQL_ROOT_PWD=$( sudo grep "temporary password" /var/log/mysqld.log | rev | cut -d' ' -f1 | rev )
	# this trickery is required to to use MySQL root password:
	# we have to add few stupid chars to pass password policy
	echo A`openssl rand -hex 10`'^%_' > $MYSQL_ROOT_PWD_FILE
	# permanent MySQL root password
	p=`cat $MYSQL_ROOT_PWD_FILE`

	# only now use temporary password
	mysql -u root --connect-expired-password -p"$MYSQL_ROOT_PWD" mysql <<EOF
SET PASSWORD FOR 'root'@'localhost' = '$p';
EOF
	# verify that permanent password really works
	mysql -u root -p"$p" -e 'show databases' mysql

	#echo "$MYSQL_ROOT_PWD" > $MYSQL_ROOT_PWD_FILE
	touch $STAGE
}

STAGE=$CFG_STAGE_DIR/pfs09c-pfms-mysql-pandoradb
[ -f $STAGE ] || {
	setup_mysql_db pandora pandora
	# verify that account is able to access database
	mysql -u pandora -p`extract_db_pwd pandora` -e 'show tables' pandora
	touch $STAGE
}

STAGE=$CFG_STAGE_DIR/pfs09d-pfms-mysql-final
[ -f $STAGE ] || {
	POOL_SIZE=$(grep -i total /proc/meminfo | head -1 | awk '{printf "%.2f \n", $(NF-1)*0.4/1024}' | sed "s/\\..*$/M/g")
	echo "New POOL_SIZE=$POOL_SIZE"
sudo tee /etc/my.cnf <<EO_CONFIG_F
[mysqld]
datadir=/var/lib/mysql
socket=/var/lib/mysql/mysql.sock
user=mysql
character-set-server=utf8mb4
skip-character-set-client-handshake
# Disabling symbolic-links is recommended to prevent assorted security risks
symbolic-links=0
# Mysql optimizations for Pandora FMS
# Please check the documentation in http://pandorafms.com for better results

max_allowed_packet = 64M
innodb_buffer_pool_size = $POOL_SIZE
innodb_lock_wait_timeout = 90
innodb_file_per_table
innodb_flush_log_at_trx_commit = 0
innodb_flush_method = O_DIRECT
innodb_log_file_size = 64M
innodb_log_buffer_size = 16M
innodb_io_capacity = 300
thread_cache_size = 8
thread_stack    = 256K
max_connections = 100

key_buffer_size=4M
read_buffer_size=128K
read_rnd_buffer_size=128K
sort_buffer_size=128K
join_buffer_size=4M

skip-log-bin

sql_mode=""

[mysqld_safe]
log-error=/var/log/mysqld.log
pid-file=/var/run/mysqld/mysqld.pid
EO_CONFIG_F

	sudo systemctl restart mysqld
	sudo systemctl enable mysqld --now

	touch $STAGE
}

# from this point MySQL must be up and both 'root' and 'pandora' account working
mysql -u root -p"`cat $MYSQL_ROOT_PWD_FILE`" -e 'show databases' mysql
mysql -u pandora -p`extract_db_pwd pandora` -e 'show tables' pandora

STAGE=$CFG_STAGE_DIR/pfs10a-install-gh-rpms
[ -f $STAGE ] || {

	# using DNF so files will populate and stay in cache dir
	# NOTE that agent uses (_) instead of (.) before arch suffix...
	# there is conflict so we first download all
# conflict:
# Error: Transaction test error:
#   file /usr/bin/tentacle_server conflicts between attempted installs of pandorafms_agent_linux_bin-7.0NG.777-1.x86_64 and pandorafms_server-7.0NG.777-1.x86_64
#   file /usr/share/man/man1/tentacle_server.1.gz conflicts between attempted installs of pandorafms_agent_linux_bin-7.0NG.777-1.x86_64 and pandorafms_server-7.0NG.777-1.x86_64

	sudo dnf install --downloadonly -y \
		https://github.com/pandorafms/pandorafms/releases/download/v${PFMS_VERXXX}-LTS/pandorafms_agent_linux_bin-${PFMS_VERFULL}_x86_64.el8.rpm \
		https://github.com/pandorafms/pandorafms/releases/download/v${PFMS_VERXXX}-LTS/pandorafms_console-${PFMS_VERFULL}.x86_64.rpm \
		https://github.com/pandorafms/pandorafms/releases/download/v${PFMS_VERXXX}-LTS/pandorafms_server-${PFMS_VERFULL}.x86_64.rpm

	# install all but Agent
	sudo dnf install -y \
		https://github.com/pandorafms/pandorafms/releases/download/v${PFMS_VERXXX}-LTS/pandorafms_console-${PFMS_VERFULL}.x86_64.rpm \
		https://github.com/pandorafms/pandorafms/releases/download/v${PFMS_VERXXX}-LTS/pandorafms_server-${PFMS_VERFULL}.x86_64.rpm

	# install Agent via RPM (this allows ignoring conflicting files)
	sudo rpm -ivh --force /var/cache/dnf/commandline-*/packages/pandorafms_agent_linux_bin-${PFMS_VERFULL}_x86_64.el8.rpm

	touch $STAGE
}

STAGE=$CFG_STAGE_DIR/pfs10b-install-gotty
[ -f $STAGE ] || {
	curl -fL -o gotty_linux_amd64.tar.gz https://firefly.pandorafms.com/pandorafms/utils/gotty_linux_amd64.tar.gz
	tar xvzf gotty_linux_amd64.tar.gz ./gotty
	sudo mv gotty /usr/bin/
	sudo chown root:root /usr/bin/gotty
	touch $STAGE
}

STAGE=$CFG_STAGE_DIR/pfs10c-enable-httpd
[ -f $STAGE ] || {
	# note: mysqld already enabled (skipped here)
	sudo systemctl enable httpd --now
	touch $STAGE
}

STAGE=$CFG_STAGE_DIR/pfs10d-pandora-schema
[ -f $STAGE ] || {
	mysql -u pandora -p`extract_db_pwd pandora` -e 'source /var/www/html/pandora_console/pandoradb.sql' pandora
	touch $STAGE
}

STAGE=$CFG_STAGE_DIR/pfs10e-pandora-data
[ -f $STAGE ] || {
	mysql -u pandora -p`extract_db_pwd pandora` -e 'source /var/www/html/pandora_console/pandoradb_data.sql' pandora
	touch $STAGE
}

STAGE=$CFG_STAGE_DIR/pfs10f-pandora-httpd
[ -f $STAGE ] || {
	p="`extract_db_pwd pandora`"
	sudo tee /var/www/html/pandora_console/include/config.php <<EO_CONFIG_F
<?php
// generated by $0 at `date`
\$config["dbtype"] = "mysql";
\$config["dbname"]="pandora";
\$config["dbuser"]="pandora";
\$config["dbpass"]="$p";
\$config["dbhost"]="127.0.0.1";
\$config["homedir"]="/var/www/html/pandora_console";
\$config["homeurl"]="/pandora_console";
// original (no error reporting at all): error_reporting(0);
error_reporting(E_ALL & ~E_NOTICE);
\$ownDir = dirname(__FILE__) . '/';
include (\$ownDir . "config_process.php");
EO_CONFIG_F

	sudo tee /etc/httpd/conf.d/pandora.conf <<EO_CONFIG_F
# generated by $0 at `date`
ServerTokens Prod
<Directory "/var/www/html">
    Options FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
EO_CONFIG_F

	sudo sed -i -e "s/php_flag engine off//g" /var/www/html/pandora_console/images/.htaccess
	sudo sed -i -e "s/php_flag engine off//g" /var/www/html/pandora_console/attachment/.htaccess

	sudo chmod 600 /var/www/html/pandora_console/include/config.php
	sudo chown apache. /var/www/html/pandora_console/include/config.php
	[ ! -f /var/www/html/pandora_console/install.php ] ||
		sudo mv /var/www/html/pandora_console/install.php /var/www/html/pandora_console/install.done

	sudo sed -i -e "s/^max_input_time.*/max_input_time = -1/g" /etc/php.ini
	sudo sed -i -e "s/^max_execution_time.*/max_execution_time = 0/g" /etc/php.ini
	sudo sed -i -e "s/^upload_max_filesize.*/upload_max_filesize = 800M/g" /etc/php.ini
	sudo sed -i -e "s/^memory_limit.*/memory_limit = 800M/g" /etc/php.ini
	sudo sed -i -e "s/.*post_max_size =.*/post_max_size = 800M/" /etc/php.ini

	echo 'TimeOut 900' | sudo tee /etc/httpd/conf.d/timeout.conf

	sudo tee /var/www/html/index.html <<EOF_INDEX
<meta HTTP-EQUIV="REFRESH" content="0; url=/pandora_console/">
EOF_INDEX

	sudo systemctl restart httpd
	sudo systemctl restart php-fpm
	touch $STAGE
}

STAGE=$CFG_STAGE_DIR/pfs10g-snmptrap
[ -f $STAGE ] || {
	sudo tee /etc/snmp/snmptrapd.conf <<EOF
authCommunity log public
disableAuthorization yes
EOF
	touch $STAGE
}

STAGE=$CFG_STAGE_DIR/pfs10h-server
[ -f $STAGE ] || {
	
	p="`extract_db_pwd pandora`"
	sudo sed -i -e "s/^dbhost.*/dbhost 127.0.0.1/g" /etc/pandora/pandora_server.conf
	sudo sed -i -e "s/^dbname.*/dbname pandora/g" /etc/pandora/pandora_server.conf
	sudo sed -i -e "s/^dbuser.*/dbuser pandora/g" /etc/pandora/pandora_server.conf
	sudo sed -i -e "s/^dbpass.*/dbpass $p/g" /etc/pandora/pandora_server.conf
	sudo sed -i -e "s/^dbport.*/dbport 3306/g" /etc/pandora/pandora_server.conf
	sudo sed -i -e "s/^#.mssql_driver.*/mssql_driver ODBC Driver 17 for SQL Server/g" /etc/pandora/pandora_server.conf

	sudo sed -i -e "s|^fping.*|fping /usr/sbin/fping|g" /etc/pandora/pandora_server.conf
	sudo sed -i "s/^remote_config.*$/remote_config 1/g" /etc/pandora/pandora_server.conf

	sudo tee /etc/pandora/pandora_server.env <<'EOF_ENV'
#!/bin/bash
VERSION=19.8
export PATH=$PATH:$HOME/bin:/usr/lib/oracle/$VERSION/client64/bin
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib/oracle/$VERSION/client64/lib
export ORACLE_HOME=/usr/lib/oracle/$VERSION/client64
EOF_ENV

	sudo tee -a /etc/sysctl.conf <<EO_KO
# Pandora FMS Optimization

# default=5
net.ipv4.tcp_syn_retries = 3

# default=5
net.ipv4.tcp_synack_retries = 3

# default=1024
net.ipv4.tcp_max_syn_backlog = 65536

# default=124928
net.core.wmem_max = 8388608

# default=131071
net.core.rmem_max = 8388608

# default = 128
net.core.somaxconn = 1024

# default = 20480
net.core.optmem_max = 81920
EO_KO

	sudo sysctl --system
	sudo chown pandora:apache /var/log/pandora
	sudo chmod g+s /var/log/pandora

	sudo tee /etc/logrotate.d/pandora_server <<EO_LR
/var/log/pandora/pandora_server.log
/var/log/pandora/web_socket.log
/var/log/pandora/pandora_server.error {
        su root apache
        weekly
        missingok
        size 300000
        rotate 3
        maxage 90
        compress
        notifempty
        copytruncate
        create 660 pandora apache
}

/var/log/pandora/pandora_snmptrap.log {
        su root apache
        weekly
        missingok
        size 500000
        rotate 1
        maxage 30
        notifempty
        copytruncate
        create 660 pandora apache
}

EO_LR

	sudo tee /etc/logrotate.d/pandora_agent <<EO_LRA
/var/log/pandora/pandora_agent.log {
        su root apache
        weekly
        missingok
        size 300000
        rotate 3
        maxage 90
        compress
        notifempty
        copytruncate
}

EO_LRA

	sudo chmod 0644 /etc/logrotate.d/pandora_server
	sudo chmod 0644 /etc/logrotate.d/pandora_agent

	# Note: enable --now does NOT work with /etc/init.d/ scripts!
	sudo systemctl enable pandora_server
	sudo service pandora_server start
	sudo systemctl enable tentacle_serverd
	sudo service tentacle_serverd start

	sudo tee -a /etc/crontab << EO_CRON
# generated by $0 at `date`
* * * * * root wget -q -O - --no-check-certificate --load-cookies /tmp/cron-session-cookies --save-cookies /tmp/cron-session-cookies --keep session-cookies http://127.0.0.1/pandora_console/enterprise/cron.php>> /var/www/html/pandora_console/log/cron.log
EO_CRON

	sudo systemctl enable --now pandora_agent_daemon
	touch $STAGE
}

STAGE=$CFG_STAGE_DIR/pfs99-fix-plugins
[ -f $STAGE ] || {

	for i in  wizard_snmp_module wizard_snmp_process
	do
		# sudo -D spits: you are not permitted to use the -D option with /bin/ln
		# because you have to enable it win 'run_cwd' to be '*' which is not default
		sudo sh -c "cd /usr/share/pandora_server/util/plugin && /usr/bin/ln -s $i.pl $i"
	done
	touch $STAGE
}

cat <<EOF

Point your browser to https://$HOST/pandora_console or https://$HOST_IP/pandora_console
Login / Password: admin / pandora

To add your first Agent:
- go to  Management -> Resources -> Manage Agents
- click on Create Agent, fill-in
EOF


exit 0
