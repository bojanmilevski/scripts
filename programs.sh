#!/bin/sh

set -e

PROGRAMS_FILE="$1"

program_exists() {
	command -v "$1" >/dev/null 2>&1
}

! program_exists paru && echo "ERROR" && exit 1
[ ! -e "$PROGRAMS_FILE" ] && echo "ERROR" && exit 1
[ -z "$PROGRAMS_FILE" ] && echo "ERROR" && exit 1

PROGRAMS="$(sed '/^#/d;/^$/d;' "$PROGRAMS_FILE")"

paru -Syy
paru -S $PROGRAMS
