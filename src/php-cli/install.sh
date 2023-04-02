#!/bin/sh
set -e

echo "Activating feature 'php-cli'"

VERSION=${VERSION:-'8.2'}
PACKAGES=${PACKAGES:-''}
TIMEZONE=${TIMEZONE:-'UTC'}
echo "The provided version is: $VERSION"
echo "The provided packages are: $PACKAGES"
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

# Environment variables
DEBIAN_FRONTEND="noninteractive"
PHP_DATE_TIMEZONE="${TIMEZONE}"
PHP_ERROR_REPORTING="22527"
PHP_MEMORY_LIMIT="256M"
PHP_MAX_EXECUTION_TIME="99"
PHP_POST_MAX_SIZE="100M"
PHP_UPLOAD_MAX_FILE_SIZE="100M"
COMPOSER_ALLOW_SUPERUSER=1
COMPOSER_HOME=/composer
COMPOSER_MAX_PARALLEL_HTTP=24

# timezone
ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# install system dependencies
apt-get update
apt-get -y --no-install-recommends install \
    software-properties-common \
    ca-certificates \
    curl \
    unzip \
    gnupg2

# Add required repository
add-apt-repository -y ppa:ondrej/php

# Install PHP
apt-get update

apt-get -y --no-install-recommends install \
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
    php${PHP_VERSION}-sqlite3

# Install Nginx Unit and PHP extensions
if [ -z "${PACKAGES}" ]; then
    packagesArr=(${PACKAGES})
    for pkg in "${packagesArr[@]}"
    do
        apt-get -y --no-install-recommends install php${PHP_VERSION}-${pkg}
    done
fi

set +e
    PHP_SRC=$(which php)
set -e

# install composer
"${PHP_SRC}" -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
HASH="$(wget -q -O - https://composer.github.io/installer.sig)"
"${PHP_SRC}" -r "if (hash_file('sha384', 'composer-setup.php') === '$HASH') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
"${PHP_SRC}" composer-setup.php --install-dir="/usr/local/bin" --filename=composer
"${PHP_SRC}" -r "unlink('composer-setup.php');"

# clean up
rm -rf /var/lib/apt/lists/*
