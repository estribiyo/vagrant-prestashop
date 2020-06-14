#!/bin/bash
# filename: bootstrap.sh

# var definition
FQDN=$1
WEBROOT="/var/www"
DOCROOT="${WEBROOT}/${FQDN}"
DBUSER=$(echo $FQDN|sed "s/\./_/g")
DBPASSWD="AUTO"                    # generamnos passwd auto
DBNAME=$(echo $FQDN|sed "s/\./_/g")
APACHE_LOG_DIR="/var/log/apache2/"
MYSQL_ROOT="root"
MYSQL_PASS="root"
SRCDIR="/usr/src"
STOREUSER="$(hostname)@$FQDN"
STOREPASS="AUTO"
PRESTAVERSION=1.7.7.x
PHPVERSION=7.3
DELETE_ON_REMOVE=0

# some colors :)
X_COL="\e[35m"
GREEN_COL="\e[32m"
RED_COL="\e[31m"
BOLD="\e[1m"
NULL_COL="\e[39m\e[0m"

if [[ "$USER" != "root" ]]
then
    exec sudo -u root "$0" "$@"
fi

function genpasswords() {
	if [ "${DBPASSWD}" == "AUTO" ]
	then
		DBPASSWD=$(pwgen -1)                    # generamnos passwd auto
	fi
	if [ "${STOREPASS}" == "AUTO" ]
	then
		STOREPASS=$(pwgen -1)
	fi
}

function modify_hosts() {
    echo -e "${GREEN_COL}Creando entrada en /etc/hosts${NULL_COL}"
    grep -qF "127.0.0.1 $FQDN www.$FQDN" /etc/hosts || echo "127.0.0.1 $FQDN www.$FQDN" >> /etc/hosts
}

function mysql_prepare() {
    MYSQL_CONNECT="mysql -u $MYSQL_ROOT -p$MYSQL_PASS -e "
    $MYSQL_CONNECT"CREATE USER \"$DBUSER\"@\"localhost\" IDENTIFIED BY \"$DBPASSWD\";"
    $MYSQL_CONNECT"GRANT USAGE ON *.* TO \"$DBUSER\"@\"localhost\" IDENTIFIED BY \"$DBPASSWD\";"
    $MYSQL_CONNECT"CREATE DATABASE IF NOT EXISTS $DBNAME;"
    $MYSQL_CONNECT"GRANT ALL ON $DBNAME.* TO $DBUSER@localhost;"
}

function requirements() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get upgrade -y
    PKGS='pwgen facter puppet curl git vim'
    WEB="mariadb-server php${PHPVERSION} php${PHPVERSION}-curl php${PHPVERSION}-intl php${PHPVERSION}-mbstring php${PHPVERSION}-zip php-mysql php${PHPVERSION}-gd php${PHPVERSION}-xml"
    for pkg in $PKGS $WEB; do
        if dpkg --get-selections | grep -q "^$pkg[[:space:]]*install$" >/dev/null; then
            echo "${pkg} previamente instalado"
        else
            if apt-get -qq install $pkg; then
                echo -e "${GREEN_COL}$pkg instalado${NULL_COL}"
            else
                echo -e "${RED_COL}Error instalando $pkg${NULL_COL}"
            fi
        fi        
    done
    if [ ! -f /usr/local/bin/composer ]; then 
    	curl -sS https://getcomposer.org/installer | /usr/bin/php -- --install-dir=/usr/local/bin --filename=composer
    fi
    if [ ! -d "${WEBROOT}/.composer" ]
    then
        echo -e "${GREEN_COL}Creando directorio caché para Composer${NULL_COL}"
        mkdir "${WEBROOT}/.composer"
    fi     
}

function prestashop_install() {
    WD=$SRCDIR/prestashop
    if [ ! -d ${WD} ]; then
        echo -e "${GREEN_COL}Clonando (Git) PrestaShop${NULL_COL}"
        git clone https://github.com/PrestaShop/PrestaShop.git ${WD}
    else
        echo -e "${GREEN_COL}${PRESTAVERSION}${NULL_COL} (${WD})"
    fi    
    cd ${WD}
    git checkout $PRESTAVERSION
    echo -e "${GREEN_COL}Preparando PrestaShop en $DOCROOT${NULL_COL}"
    mkdir $DOCROOT
    cp $WD/* $DOCROOT -Rf
    chown www-data:www-data $DOCROOT -Rf
    chmod g+w $DOCROOT -Rf 
    cd $DOCROOT
    if [ -f composer.json ]; then
        sudo -u www-data composer install  
    fi    
    /usr/bin/php install-dev/index_cli.php --email=$STOREUSER --password=$STOREPASS --domain=$FQDN --db_server=localhost --db_name=$DBNAME --db_user=$DBUSER --db_password=$DBPASSWD --country=es --language=es --newsletter=0
    chown www-data:www-data $DOCROOT -Rf
    chmod g+w $DOCROOT -Rf    
}

function recaptcha_plugin_install () {
    echo -e "${GREEN_COL}Instalando ReCaptcha${NULL_COL}"
    if [ ! -d $SRCDIR/eicaptcha ]; then
        echo -e "${GREEN_COL}Clonando (Git) eicaptcha${NULL_COL}"
        git clone https://github.com/nenes25/eicaptcha.git $SRCDIR/eicaptcha 
    fi
    if [ -d $DOCROOT/modules/eicaptcha ]; then
        rm $DOCROOT/modules/eicaptcha -Rf
    fi    
    echo -e "${GREEN_COL}Preparando plugin eicaptcha${NULL_COL}"
    cp $SRCDIR/eicaptcha $DOCROOT/modules/eicaptcha -r
    cd $DOCROOT/modules/eicaptcha
    chown www-data:www-data . -Rf
    chmod g+w . -Rf    
    sudo -u www-data composer install      
}

function enable_site() {
    echo -e "${GREEN_COL}Configurando Apache2 web server${NULL_COL}"
    echo "<VirtualHost *:80>"  > /etc/apache2/sites-available/$FQDN.conf
    echo " ServerName $FQDN" >> /etc/apache2/sites-available/$FQDN.conf
    echo " ServerAlias www.$FQDN" >> /etc/apache2/sites-available/$FQDN.conf
    echo " ServerAdmin webmaster@$FQDN" >> /etc/apache2/sites-available/$FQDN.conf
    echo " DocumentRoot $DOCROOT/" >> /etc/apache2/sites-available/$FQDN.conf
    echo " ErrorLog ${APACHE_LOG_DIR}$FQDN-error.log" >> /etc/apache2/sites-available/$FQDN.conf
    echo " CustomLog ${APACHE_LOG_DIR}$FQDN-access.log combined" >> /etc/apache2/sites-available/$FQDN.conf
    echo " <Directory $DOCROOT>" >> /etc/apache2/sites-available/$FQDN.conf        
    echo "  Options Indexes FollowSymLinks MultiViews" >> /etc/apache2/sites-available/$FQDN.conf
    echo "  AllowOverride all" >> /etc/apache2/sites-available/$FQDN.conf
    echo "  <IfVersion < 2.4>" >> /etc/apache2/sites-available/$FQDN.conf
    echo "    Allow from all" >> /etc/apache2/sites-available/$FQDN.conf
    echo "  </IfVersion>" >> /etc/apache2/sites-available/$FQDN.conf
    echo "  <IfVersion >= 2.4>" >> /etc/apache2/sites-available/$FQDN.conf
    echo "    Require all granted" >> /etc/apache2/sites-available/$FQDN.conf
    echo "  </IfVersion>" >> /etc/apache2/sites-available/$FQDN.conf
    echo " </Directory>" >> /etc/apache2/sites-available/$FQDN.conf
    echo "</VirtualHost>" >> /etc/apache2/sites-available/$FQDN.conf

    echo -e "${GREEN_COL}Activando site en Apache${NULL_COL}"
    a2enmod rewrite
    a2ensite $FQDN > /dev/null
    a2dissite 000-default 
    /etc/init.d/apache2 restart
}

function remove() {
    echo -e "${RED_COL}Desactivando site en Apache${NULL_COL}"
    a2dissite $FQDN > /dev/null
    /etc/init.d/apache2 restart
    if [ "${DELETE_ON_REMOVE}" -ne "0" ]
    then
        echo -e "${RED_COL}Eliminando site $DOCROOT${NULL_COL}"
        rm -Rf $DOCROOT
    else
        echo -e "${GREEN_COL}Se guarda una copia en ${DOCROOT}.$(date +%Y%m%d_%H%M).back${NULL_COL}"
        mv $DOCROOT ${DOCROOT}.`date +%Y%m%d_%H%M`.bak
    fi
}

function cleandb() {
    echo -e "${RED_COL}Eliminando usuario y BBDD${NULL_COL}"
    MYSQL_CONNECT="mysql -u $MYSQL_ROOT -p$MYSQL_PASS -e "
    $MYSQL_CONNECT"DROP USER \"$DBUSER\"@\"localhost\";"
    $MYSQL_CONNECT"DROP DATABASE $DBNAME;"
}

function rm_hosts() {
    echo -e "${RED_COL}Eliminando nombre de host${NULL_COL}"
    sed -i "/127.0.0.1 ${FQDN} www.${FQDN}/d" /etc/hosts
}

function resumen() {
	echo -e "${GREEN_COL}${DOCROOT}/resumen.txt${NULL_COL}\n"
	echo -e "${X_COL}========== R E S U M E N ====================================\n${NULL_COL}" > ${DOCROOT}/resumen.txt
	echo -e "${GREEN_COL}MySQL (MariaDB, ...)${NULL_COL}\n\tUsuario:\t${X_COL}$DBUSER${NULL_COL}\n\tPassword:\t${X_COL}$DBPASSWD${NULL_COL}" >> ${DOCROOT}/resumen.txt
	echo -e "\n${GREEN_COL}http://www.${FQDN}/admin-dev${NULL_COL}\n\tUsuario:\t${X_COL}$STOREUSER${NULL_COL}\n\tPassword:\t${X_COL}$STOREPASS${NULL_COL}" >> ${DOCROOT}/resumen.txt
	echo -e "\n${X_COL}=============================================================\n${NULL_COL}" >> ${DOCROOT}/resumen.txt
	cat ${DOCROOT}/resumen.txt
}

if [ ! -d $DOCROOT ]
then
    requirements
    genpasswords
    mysql_prepare
    prestashop_install
    recaptcha_plugin_install
    modify_hosts
    enable_site
    resumen
else
    echo -e "${RED_COL}WARN: Este website ya existe, asegúrate de lo que estas haciendo. ;)${NULL_COL}"
    echo -e "${BOLD}${RED_COL}Se eliminará la configuración de $FQDN (ctrl+c para detener)${NULL_COL}"
    sleep 30s
    remove
    cleandb
    rm_hosts
fi


