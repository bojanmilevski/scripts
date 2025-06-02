#!/bin/sh

set -e

. "./utils.sh"
include_env

# user groups
## as root
usermod -aG "${USER_GROUPS}" "${USER_NAME}"

# services
## as root
rc-update add "user.${USER_NAME}" default
for service in $SYSTEM_SERVICES; do
  rc-update add "$service" default
done

## as user
for service in $USER_SERVICES; do
  rc-update --user add "/etc/user/init.d/$service" default
done
