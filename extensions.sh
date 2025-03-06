#!/bin/sh

set -e

source "$(basename "$0")/header.sh"

! program_exists "gex" && echo "gex is not installed! Installing..." && paru -S "gex-git"

gex i -b \
	"bitwarden-password-manager" \
	"clearurls" \
	"cookie-autodelete" \
	"darkreader" \
	"decentraleyes" \
	"df-youtube" \
	"disconnect" \
	"facebook-container" \
	"google-container" \
	"istilldontcareaboutcookies" \
	"librewolf" \
	"passff" \
	"privacy-badger17" \
	"return-youtube-dislikes" \
	"sponsorblock" \
	"terms-of-service-didnt-read" \
	"uaswitcher" \
	"ublock-origin" \
	"vimium-ff" \
	"volume-control-boost-volume" \
	"youtube-nonstop"
