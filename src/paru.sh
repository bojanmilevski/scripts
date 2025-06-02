#!/bin/sh

set -ex

. "./utils.sh"

fail_if_root

program_exists "paru" && echo "paru is already installed" && exit 0
! program_exists "git" && pacman -Syy && pacman -S git
! program_exists "cargo" && pacman -Syy && pacman -S cargo

git clone "https://aur.archlinux.org/paru.git" "$HOME/paru"
cd "$HOME/paru"
makepkg -is
cd "-"
rm -rf "$HOME/paru"
