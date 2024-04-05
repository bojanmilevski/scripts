#!/bin/sh

set -e

program_exists() {
	command -v "$1" >/dev/null 2>&1
}

program_exists "paru" && echo "paru already installed" && exit 1
! program_exists "git" && sudo pacman -Syy && sudo pacman -S git
! program_exists "cargo" && sudo pacman -Syy && sudo pacman -S cargo

git clone "https://aur.archlinux.org/paru.git" "$HOME/paru"
cd "$HOME/paru"
makepkg -si "paru"
rm -rf "$HOME/paru"
cd "-"
