#!/bin/bash
set -ex

echo "Activating feature 'nginx-unit-php'"

PORT=80
APP_ROOT=${PWD}
CONFIG_PATH=/nginx-unit/config.json

echo "The provided port is: $PORT"
echo "The provided app root path is: $APP_ROOT"
echo "The provided config path is: $CONFIG_PATH"

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

# Create the entrypoint
mkdir /nginx-unit

export PHP_PATH=$(which php)
export PHP_VERSION=$(bash -c "$PHP_PATH --version")

echo "PHP INSTALLED >> $PHP_VERSION at $PATH_PATH"

####################################################################
### COMPILE UNIT
####################################################################

apt-get update

# Install required dependencies to build the Unit and module

apt-get install --no-install-recommends --no-install-suggests -y \
    curl \
    ca-certificates \
    build-essential \
    libssl-dev \
    libpcre2-dev \
    php${PHP_VERSION}-dev \
    libphp${PHP_VERSION}-embed

mkdir -p /usr/lib/unit/modules /usr/lib/unit/debug-modules

curl -O https://unit.nginx.org/download/unit-1.29.1.tar.gz
tar xzf unit-1.29.1.tar.gz
cd unit-1.29.1

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
if [ -f "/tmp/libunit.a" ]; then
    mv /tmp/libunit.a /usr/lib/$(dpkg-architecture -q DEB_HOST_MULTIARCH)/libunit.a;
    rm -f /tmp/libunit.a;
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
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -f /nginx-unit/requirements.apt

####################################################################
### GENERATE SCRIPTS TO GET UNIT UP AND RUNNING
####################################################################

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
                        "share": "${APP_ROOT}\$uri",
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
