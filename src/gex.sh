#!/bin/sh

set -ex

fail_if_root

. "./utils.sh"

! program_exists "gex" && echo "gex is not installed! Installing..." && paru -S "gex-git"

ADDONS_FILE="./browser_addons.txt"

[ ! -e "$ADDONS_FILE" ] && echo "File with addons list does not exist!" && exit 1
[ -z "$ADDONS_FILE" ] && echo "File with addons list is empty!" && exit 1

ADDONS="$(sed '/^#/d;/^$/d;' "$ADDONS_FILE")"

gex i -b "librewolf" $ADDONS
