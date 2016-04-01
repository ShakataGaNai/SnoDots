#!/usr/bin/env bash

########
# Docs #
########

# install.sh
# Exit codes
# 1 - usage error

############
# Modpacks #
############

typeset -A packs
packs[lite]="zsh commonsh vim top git screen"
packs[heavy]="zsh-syntax-highlighting"
packs[desktop]="conky"
packs[windows]="mintty"
packs[okta-zsh]=""

########
# Code #
########

# Boring, house-keeping stuff
cd $( dirname $0 )
typeset -A packages
loglevel=1
OS="null"

function log() {
	if [ $loglevel -ge $1 ]; then
		thisloglevel=$1
		shift
		case $thisloglevel in
			0)
				logstr=""
				;;
			1)
				logstr="WARNING: "
				;;
			2)
				logstr="VERBOSE: "
				;;
			3)
				logstr="DEBUG: "
				;;
			*)
				logstr="LOG: "
				;;
		esac
		echo "${logstr}$@"
	fi
}

# Slightly more interesting
function clear_dots() {
# do something with the .trackedfiles var to compare against git repo
#	cat <<WARN > ${HOME}/.dots/README
#EVERYTHING IN THIS DIRECTORY WILL BE DELETED
#WHEN SNODOTS INSTALLER RUNS AGAIN. BEWARE!
#WARN
}

clear_dots zsh
exit 99

find_linux_distro() {
	[ -e /etc/os-release ] && relfile="/etc/os-release" || relfile="/usr/lib/os-release"
	if [ -n "$relfile" ]; then
		OS=$( cat /etc/os-release|grep -G '^ID='|cut -d= -f2|tr -d \" )
	else
		OS="unknown-linux"
	fi
}

find_os() {
	case $( uname -s | tr [:upper:] [:lower:] ) in
		cygwin*)
			OS="windows"
			;;
		linux)
			find_linux_distro
			;;
		darwin)
			OS="macos"
			;;
		sunos)
			OS="sunos"
			;;
		*)
			OS="unknown"
			;;
	esac
}
add_package() {
	declare key=$1
	declare val=$2
	if [ "x${packages["$key"]}" == "x" ]; then
		log 3 "Adding package $key as $val from $searchOS"
		packages["$key"]=$val
	else
		log 2 "Skip adding package $key as $val from $searchOS -- already set to ${packages["$key"]}"
	fi
}

gen_package_list() {
	log 2 "Generating packages for $OS..."
	[ "x$1" == "x" ] && searchOS=$OS || searchOS=$1
	typeset -a results
	results=( $( awk -f iniparse.awk packagedb.ini | grep -i $searchOS. ) )
	typeset -a inherits
	for i in ${results[@]}; do
		declare key=$( cut -d. -f2 <<< $i | cut -d= -f1 )
		declare val=$( cut -d= -f2 <<< $i )
		if [ $key == "_INHERIT" ]; then
			inherits[${#inherits[*]}]=$val
			continue
		fi
		add_package $key $val
	done
	for i in ${inherits[@]}; do
		log 3 "Inheriting from $i..."
		gen_package_list $i
	done
}

function command_append() {
	# $2 - source file; $3 - dest to append
	log 2 "Appending data from $2 to $3"
	cat ${HOME}/.dots/$1/$2 >> $( eval echo $3 )
}

function command_place() {
	# $2 - source; $3 - destination
	if [ -h $3 ]; then
		rm $3
	elif [ -e $3 ]; then
		log 0 "Skipping placement of $3; file already exists and is not a link"
		return 1
	fi
	log 2 "Linking $2 at $3..."
	ln -s ${HOME}/.dots/$1/$2 $( eval echo $3 )
}

function command_package() {
	# $2 - package
	if [ "x$packages_generated" == "x" ]; then
		log 0 "Generating package map..."
		gen_package_list
		packages_generated=true
	fi

	if [ "x$2" == "x" ]; then
		log 1 "No package name given for package directive"
		return
	elif [ "x${packages[$2]}" == "x" ]; then
		log 1 "No distro-specific map for package: $2; trying the raw string"
		packages[$2]=$2
	fi
	declare pkgcmd
	case $OS in
		cygwin*)
			pkgcmd="cyg-get install -y "
			;;
		debian)
			pkgcmd="sudo apt-get install -y "
			;;
		ubuntu)
			pkgcmd="sudo apt-get install -y "
			;;
		mint)
			pkgcmd="sudo apt-get install -y "
			;;
		centos)
			pkgcmd="sudo yum install -y "
			;;
		fedora)
			pkgcmd="sudo yum install -y "
			;;
		*)
			pkgcmd="echo Please install the following packages: "
			;;
	esac
	$pkgcmd ${packages[$2]}
}

function command_execute() {
	# $2 - script; $3-$N - args for script
	script=${HOME}/.dots/$1/$2
	shift
	$script $@
}

function show_usage() {
	cat <<HELP
Usage: $0 [OPTIONS] [ARGS]

Available options:
	-h			show this message
	-p [pack]	specify a mod pack to install
	-m [mod]	specify a single mod to install
	-v			verbose output
	-q			supress warnings
HELP
}

function run_modpack() {
	if [ "x${packs[$1]}" == "x" ]; then
		echo "Skipping $1 pack -- nonexistent or empty"
	else
		echo "Running modpack $1 ..."
		for mod in ${packs[$1]}; do
			run_mod $mod
		done
	fi
}

copy_mod() {
	cp -r $1 ${HOME}/.dots/
	find ${HOME}/.dots/$1 >> ${HOME}/.dots/.trackedfiles
}

function run_mod() {
	declare mod = $1
	echo "Running mod $mod ..."
	clear_dots $mod
	copy_mod $mod
	# Actions: append, place, package
	if [ -e $mod/props.txt ]; then
		IFS=$'\n'
		for line in $(cat $mod/props.txt); do
			unset IFS
			cmd=$( echo $line | cut -f1 -d= | tr [:upper:] [:lower:] )
			args=$( echo $line | cut -f2- -d= )
			log 3 "cmd: $cmd; args: $args"
			case $cmd in
				\#*)
					;;
				append)
					command_append $mod $args
					;;
				place)
					command_place $mod $args
					;;
				execute)
					command_execute $mod $args
					;;
				package)
					command_package $mod $args
					;;
				*)
					echo "Unknown command $cmd in mod $mod"
					;;
			esac
		done
	else
		# Simple mod; no props file
		# Drop everything into ~ with a . in front of it
		for file in $(ls $1); do
			command_place $file \${HOME}/.$file
		done
	fi
}

find_os
while getopts ":p:m:hqv" opts; do
	case $opts in
		h)
			show_usage
			exit 0
			;;
		p)
			run_modpack $OPTARG
			;;
		m)
			run_mod $OPTARG
			;;
		v)
			loglevel=$( expr $loglevel + 1 )
			log 3 Set log level to $loglevel
			;;
		q)
			loglevel=0
			log 3 Set log level to $loglevel
			;;
		*)
			echo "Unknown option: $OPTARG"
			show_usage
			exit 1
			;;
	esac
done
