#!/bin/sh

set -e

RESET="\033[0m"
BOLD="\033[1m"
BLACK="\033[30m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
MAGENTA="\033[35m"
CYAN="\033[36m"
WHITE="\033[37m"

error() {
  echo "${BOLD}${RED}${1}${RESET}"
  exit 1
}

program_exists() {
  command -v "$1" >/dev/null 2>&1
}

check_if_root() {
  [ "$(whoami)" != "root" ] && error "You need to run this script as root!"
}

fail_if_root() {
  [ "$(whoami)" = "root" ] && error "This script cannot be run as root!"
}

execute() {
  "./${1}.sh"
}

include() {
  . "./${1}.sh"
}

include_env() {
  . "./.env"
}
