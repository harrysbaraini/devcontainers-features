#!/bin/bash
set -eux

echo "Activating feature 'nginx-unit-php'"

echo "The provided port is: $PORT"
echo "The provided app root path is: $APP_ROOT"
echo "The provided config path is: $CONFIG_PATH"
echo "The provided version is: $PHP_VERSION"
echo "The provided packages are: $PHP_PACKAGES"
echo "The provided timezone is: $TIMEZONE"

# The 'install.sh' entrypoint script is always executed as the root user.
#
# These following environment variables are passed in by the dev container CLI.
# These may be useful in instances where the context of the final
# remoteUser or containerUser is useful.
# For more details, see https://containers.dev/implementors/features#user-env-var
echo "The effective dev container remoteUser is '$_REMOTE_USER'"
echo "The effective dev container remoteUser's home directory is '$_REMOTE_USER_HOME'"

echo "The effective dev container containerUser is '$_CONTAINER_USER'"
echo "The effective dev container containerUser's home directory is '$_CONTAINER_USER_HOME'"

export DEBIAN_FRONTEND=noninteractive
echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

PHP_DATE_TIMEZONE="${TIMEZONE}"
PHP_ERROR_REPORTING="22527"
PHP_MEMORY_LIMIT="256M"
PHP_MAX_EXECUTION_TIME="99"
PHP_POST_MAX_SIZE="100M"
PHP_UPLOAD_MAX_FILE_SIZE="100M"
COMPOSER_ALLOW_SUPERUSER=1
COMPOSER_HOME=/composer
COMPOSER_MAX_PARALLEL_HTTP=24

mkdir /nginx-unit

# install system dependencies

apt-get update

apt-get -yq --no-install-recommends install \
    software-properties-common \
    ca-certificates \
    mercurial \
    build-essential \
    libssl-dev \
    libpcre2-dev \
    curl \
    unzip \
    gnupg2

# Install PHP

add-apt-repository -y ppa:ondrej/php

apt-get update

apt-get -yq --no-install-recommends install \
    php${PHP_VERSION}-cli \
    php${PHP_VERSION}-common \
    php${PHP_VERSION}-igbinary \
    php${PHP_VERSION}-readline \
    php${PHP_VERSION}-curl \
    php${PHP_VERSION}-intl \
    php${PHP_VERSION}-curl \
    php${PHP_VERSION}-tokenizer \
    php${PHP_VERSION}-mbstring \
    php${PHP_VERSION}-bcmath \
    php${PHP_VERSION}-xml \
    php${PHP_VERSION}-zip \
    php${PHP_VERSION}-sqlite3 \
    ${PHP_PACKAGES}

# install composer

php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
HASH="$(wget -q -O - https://composer.github.io/installer.sig)"
php -r "if (hash_file('sha384', 'composer-setup.php') === '$HASH') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
php composer-setup.php --install-dir="/usr/local/bin" --filename=composer
php -r "unlink('composer-setup.php');"

# Compile Unit

mkdir -p /usr/lib/unit/modules /usr/lib/unit/debug-modules
hg clone https://hg.nginx.org/unit
cd unit
hg up 1.29.1
NCPU="$(getconf _NPROCESSORS_ONLN)"
DEB_HOST_MULTIARCH="$(dpkg-architecture -q DEB_HOST_MULTIARCH)"
CC_OPT="$(DEB_BUILD_MAINT_OPTIONS="hardening=+all,-pie" DEB_CFLAGS_MAINT_APPEND="-Wp,-D_FORTIFY_SOURCE=2 -fPIC" dpkg-buildflags --get CFLAGS)"
LD_OPT="$(DEB_BUILD_MAINT_OPTIONS="hardening=+all,-pie" DEB_LDFLAGS_MAINT_APPEND="-Wl,--as-needed -pie" dpkg-buildflags --get LDFLAGS)"
CONFIGURE_ARGS="--prefix=/usr \
                --state=/var/lib/unit \
                --control=unix:/var/run/control.unit.sock \
                --pid=/var/run/unit.pid \
                --log=/var/log/unit.log \
                --tmp=/var/tmp \
                --user=unit \
                --group=unit \
                --openssl \
                --libdir=/usr/lib/$DEB_HOST_MULTIARCH"

./configure $CONFIGURE_ARGS --cc-opt="$CC_OPT" --ld-opt="$LD_OPT" --modules=/usr/lib/unit/debug-modules --debug
make -j $NCPU unitd
install -pm755 build/unitd /usr/sbin/unitd-debug
make clean
./configure $CONFIGURE_ARGS --cc-opt="$CC_OPT" --ld-opt="$LD_OPT" --modules=/usr/lib/unit/modules
make -j $NCPU unitd
install -pm755 build/unitd /usr/sbin/unitd
make clean
./configure $CONFIGURE_ARGS --cc-opt="$CC_OPT" --modules=/usr/lib/unit/debug-modules --debug
./configure php
make -j $NCPU php-install
make clean
./configure $CONFIGURE_ARGS --cc-opt="$CC_OPT" --modules=/usr/lib/unit/modules
./configure php
make -j $NCPU php-install
ldd /usr/sbin/unitd | awk '/=>/{print $(NF-1)}' | while read n; do dpkg-query -S $n; done | sed 's/^\([^:]\+\):.*$/\1/' | sort | uniq > /nginx-unit/requirements.apt
ldconfig

if [ -f "/tmp/libunit.a" ]; then \
    mv /tmp/libunit.a /usr/lib/$(dpkg-architecture -q DEB_HOST_MULTIARCH)/libunit.a; \
    rm -f /tmp/libunit.a; \
fi

mkdir -p /var/lib/unit/
addgroup --system unit
adduser \
    --system \
    --disabled-login \
    --ingroup unit \
    --no-create-home \
    --home /nonexistent \
    --gecos "unit user" \
    --shell /bin/false \
    unit

apt update
apt --no-install-recommends --no-install-suggests -y install curl $(cat /nginx-unit/requirements.apt)
rm /nginx-unit/requirements.apt
apt-get remove mercurial
apt-get clean

# Create the entrypoint

cat << EOFFILE > /usr/local/bin/nginx-unit.sh
#!/bin/bash

set -e
WAITLOOPS=5
SLEEPSEC=1

generate_config()
{
    if [ ! -f /nginx-unit/config.json ]; then
        cat << EOFCONFIG > /nginx-unit/config.json
        {
            "listeners": {
                "*:${PORT}": {
                    "pass": "routes"
                }
            },

            "routes": [
                {
                    "match": {
                        "uri": "!/index.php"
                    },
                    "action": {
                        "share": "${APP_ROOT}\\$uri",
                        "fallback": {
                            "pass": "applications/php"
                        }
                    }
                }
            ],

            "applications": {
                "php": {
                    "type": "php",
                    "root": "${APP_ROOT}/",
                    "script": "index.php",
                    "user": "${_REMOTE_USER}"
                }
            }
        }
EOFCONFIG
    fi
}

load_config()
{
    RET=\$(/usr/bin/curl -s -w '%{http_code}' -X PUT --data-binary @/${CONFIG_PATH} --unix-socket /var/run/control.unit.sock http://localhost/config)
    RET_BODY=\$(echo \$RET | /bin/sed '\$ s/...\$//')
    RET_STATUS=\$(echo \$RET | /usr/bin/tail -c 4)
    if [ "\$RET_STATUS" -ne "200" ]; then
        echo "\$0: Error: HTTP response status code is '\$RET_STATUS'"
        echo "\$RET_BODY"
        return 1
    else
        echo "\$0: OK: HTTP response status code is '\$RET_STATUS'"
        echo "\$RET_BODY"
    fi
    return 0
}

/usr/sbin/unitd --control unix:/var/run/control.unit.sock

for i in \$(/usr/bin/seq \$WAITLOOPS); do
    if [ ! -S /var/run/control.unit.sock ]; then
        echo "\$0: Waiting for control socket to be created..."
        /bin/sleep \$SLEEPSEC
    else
        break
    fi
done

# even when the control socket exists, it does not mean unit has finished initialisation
# this curl call will get a reply once unit is fully launched
/usr/bin/curl -s -X GET --unix-socket /var/run/control.unit.sock http://localhost/

echo "\$0: Apply configuration"
generate_config
load_config

echo
echo "\$0: Unit initial configuration complete; Nginx Unit ready."
echo

exec
EOFFILE

chmod a+x /usr/local/bin/nginx-unit.sh

# clean up

rm -rf /var/lib/apt/lists/*
