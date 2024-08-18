#!/bin/sh

set -e

DIR="$(dirname "$0")"
source "$DIR/header.sh"

! program_exists "paru" && echo "paru is not installed. Installing ..." && "$DIR/paru.sh"

PROGRAMS_FILE="$DIR/programs.txt"

[ ! -e "$PROGRAMS_FILE" ] && echo "File with programs list does not exist!" && exit 1
[ -z "$PROGRAMS_FILE" ] && echo "File with programs list is empty!" && exit 1

PROGRAMS="$(sed '/^#/d;/^$/d;' "$PROGRAMS_FILE")"

paru -Syy
paru -S $PROGRAMS
