#!/bin/bash
set -eux

echo "Activating feature 'php-cli'"

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
export DEBIAN_FRONTEND=noninteractive

PHP_DATE_TIMEZONE="${TIMEZONE}"
PHP_ERROR_REPORTING="22527"
PHP_MEMORY_LIMIT="256M"
PHP_MAX_EXECUTION_TIME="99"
PHP_POST_MAX_SIZE="100M"
PHP_UPLOAD_MAX_FILE_SIZE="100M"
COMPOSER_ALLOW_SUPERUSER=1
COMPOSER_HOME=/composer
COMPOSER_MAX_PARALLEL_HTTP=24

echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

# install system dependencies
apt-get update
apt-get -y --no-install-recommends install \
    software-properties-common \
    ca-certificates \
    curl \
    unzip \
    gnupg2 \
    wget

# Add required repository
add-apt-repository -y ppa:ondrej/php
apt-get update

# Install PHP
apt-get -y --no-install-recommends install php${VERSION}-{cli,common,igbinary,readline,curl,intl,curl,mbstring,bcmath,xml,zip,sqlite3}

if [ -z "${PACKAGES}" ]; then
    apt-get -y --no-install-recomends install php${VERSION}-{$PACKAGES}
fi

# install composer
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
HASH="$(wget -q -O - https://composer.github.io/installer.sig)"
php -r "if (hash_file('sha384', 'composer-setup.php') === '$HASH') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
php composer-setup.php --install-dir="/usr/local/bin" --filename=composer
php -r "unlink('composer-setup.php');"

# clean up
rm -rf /var/lib/apt/lists/*
