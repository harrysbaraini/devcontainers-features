#!/bin/bash
set -eux

echo "Activating feature 'nginx-unit-php'"

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

# Add required apt repositories
curl --output /usr/share/keyrings/nginx-keyring.gpg https://unit.nginx.org/keys/nginx-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/nginx-keyring.gpg] https://packages.nginx.org/unit/ubuntu/ jammy unit" > /etc/apt/sources.list.d/unit.list \
    && echo "deb-src [signed-by=/usr/share/keyrings/nginx-keyring.gpg] https://packages.nginx.org/unit/ubuntu/ jammy unit" >> /etc/apt/sources.list.d/unit.list

apt-get update
apt-get -yq --no-install-recommends install \
    unit \
    unit-php


# Create the entrypoint
mkdir /nginx-unit

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
