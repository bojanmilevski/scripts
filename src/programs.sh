#!/bin/sh

set -ex

. "./utils.sh"

fail_if_root

! program_exists "paru" && echo "paru is not installed. Installing ..." && ./paru.sh

PROGRAMS_FILE="./programs.txt"

[ ! -e "$PROGRAMS_FILE" ] && echo "File with programs list does not exist!" && exit 1
[ -z "$PROGRAMS_FILE" ] && echo "File with programs list is empty!" && exit 1

PROGRAMS="$(sed '/^#/d;/^$/d;' "$PROGRAMS_FILE")"

paru -Syy
paru -S $PROGRAMS
