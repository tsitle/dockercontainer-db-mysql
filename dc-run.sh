#!/bin/bash

#
# by TS, Jan 2020
#

# ----------------------------------------------------------

# update Docker Image from remote repository? [true|false]
LCFG_UPDATE_REMOTE_IMAGE=true

# ----------------------------------------------------------

# @param string $1 Path
# @param int $2 Recursion level
#
# @return string Absolute path
function realpath_osx() {
	local TMP_RP_OSX_RES=
	[[ $1 = /* ]] && TMP_RP_OSX_RES="$1" || TMP_RP_OSX_RES="$PWD/${1#./}"

	if [ -h "$TMP_RP_OSX_RES" ]; then
		TMP_RP_OSX_RES="$(readlink "$TMP_RP_OSX_RES")"
		# possible infinite loop...
		local TMP_RP_OSX_RECLEV=$2
		[ -z "$TMP_RP_OSX_RECLEV" ] && TMP_RP_OSX_RECLEV=0
		TMP_RP_OSX_RECLEV=$(( TMP_RP_OSX_RECLEV + 1 ))
		if [ $TMP_RP_OSX_RECLEV -gt 20 ]; then
			# too much recursion
			TMP_RP_OSX_RES="--error--"
		else
			TMP_RP_OSX_RES="$(realpath_osx "$TMP_RP_OSX_RES" $TMP_RP_OSX_RECLEV)"
		fi
	fi
	echo "$TMP_RP_OSX_RES"
}

# @param string $1 Path
#
# @return string Absolute path
function realpath_poly() {
	case "$OSTYPE" in
		linux*) realpath "$1" ;;
		darwin*) realpath_osx "$1" ;;
		*) echo "$VAR_MYNAME: Error: Unknown OSTYPE '$OSTYPE'" >/dev/stderr; echo -n "$1" ;;
	esac
}

VAR_MYNAME="$(basename "$0")"
VAR_MYDIR="$(realpath_poly "$0")"
VAR_MYDIR="$(dirname "$VAR_MYDIR")"

# ----------------------------------------------------------

# Outputs CPU architecture string
#
# @param string $1 debian_rootfs|debian_dist
#
# @return int EXITCODE
function _getCpuArch() {
	case "$(uname -m)" in
		x86_64*)
			echo -n "amd64"
			;;
		i686*)
			if [ "$1" = "debian_dist" ]; then
				echo -n "i386"
			else
				echo "$VAR_MYNAME: Error: invalid arg '$1'" >/dev/stderr
				return 1
			fi
			;;
		aarch64*)
			if [ "$1" = "debian_rootfs" ]; then
				echo -n "arm64v8"
			elif [ "$1" = "debian_dist" ]; then
				echo -n "arm64"
			else
				echo "$VAR_MYNAME: Error: invalid arg '$1'" >/dev/stderr
				return 1
			fi
			;;
		armv7*)
			if [ "$1" = "debian_rootfs" ]; then
				echo -n "arm32v7"
			elif [ "$1" = "debian_dist" ]; then
				echo -n "armhf"
			else
				echo "$VAR_MYNAME: Error: invalid arg '$1'" >/dev/stderr
				return 1
			fi
			;;
		*)
			echo "$VAR_MYNAME: Error: Unknown CPU architecture '$(uname -m)'" >/dev/stderr
			return 1
			;;
	esac
	return 0
}

_getCpuArch debian_dist >/dev/null || exit 1

# ----------------------------------------------------------

function printUsageAndExit() {
	echo "Usage: $VAR_MYNAME <VERSION>" >/dev/stderr
	echo "Examples: $VAR_MYNAME 5.7" >/dev/stderr
	echo "          $VAR_MYNAME 8.0" >/dev/stderr
	exit 1
}

if [ $# -eq 1 ] && [ "$1" = "-h" -o "$1" = "--help" ]; then
	printUsageAndExit
fi

if [ $# -lt 1 ]; then
	echo -e "Missing argument. Aborting.\n" >/dev/stderr
	printUsageAndExit
fi

OPT_IMG_VER="$1"
shift

cd "$VAR_MYDIR" || exit 1

# ----------------------------------------------------------

LCFG_MYSQL_USER_ID=
LCFG_MYSQL_GROUP_ID=

TMP_UID="$(id -u)"
TMP_GID="$(id -g)"
[ $TMP_UID -gt 499 ] && LCFG_MYSQL_USER_ID=$TMP_UID
[ $TMP_GID -gt 100 ] && LCFG_MYSQL_GROUP_ID=$TMP_GID

# ----------------------------------------------------------

LVAR_IMG_VER_SHORT="$(echo -n "$OPT_IMG_VER" | cut -f1-2 -d.)"
TMP_IMGVER_STR="$(echo -n "$LVAR_IMG_VER_SHORT" | tr -d .)"

echo -n "$LVAR_IMG_VER_SHORT" | grep -q -E "[0-9]{1,2}[\.][0-9]{1,2}" || {
	echo "Invalid version. Must have format 'xx.xx'." >/dev/stderr
	exit 1
}

# ----------------------------------------------------------

LVAR_CNF_FN="dc-conf-${LVAR_IMG_VER_SHORT}.cnf"

if [ ! -f "$LVAR_CNF_FN" ]; then
	echo "Config file '$LVAR_CNF_FN' not found. Aborting." >/dev/stderr
	exit 1
fi

. "$LVAR_CNF_FN"

[ -n "$CFG_SYSUSR_MYSQL_USER_ID" ] && LCFG_MYSQL_USER_ID=$CFG_SYSUSR_MYSQL_USER_ID
[ -n "$CFG_SYSUSR_MYSQL_GROUP_ID" ] && LCFG_MYSQL_GROUP_ID=$CFG_SYSUSR_MYSQL_GROUP_ID

[ -n "$CF_MYSQL_SQLMODE" ] && CF_MYSQL_SQLMODE="$(echo -n "$CF_MYSQL_SQLMODE" | tr -d [:space:])"

# ----------------------------------------------------------

LVAR_REPO_PREFIX="tsle"
LVAR_IMAGE_NAME="db-mysql-$(_getCpuArch debian_dist)"
LVAR_IMAGE_VER="$LVAR_IMG_VER_SHORT"

LVAR_IMG_FULL="${LVAR_IMAGE_NAME}:${LVAR_IMAGE_VER}"

# ----------------------------------------------------------

# @param string $1 Docker Image name
# @param string $2 optional: Docker Image version
#
# @returns int If Docker Image exists 0, otherwise 1
function _getDoesDockerImageExist() {
	local TMP_SEARCH="$1"
	[ -n "$2" ] && TMP_SEARCH="$TMP_SEARCH:$2"
	local TMP_AWK="$(echo -n "$1" | sed -e 's/\//\\\//g')"
	#echo "  checking '$TMP_SEARCH'"
	local TMP_IMGID="$(docker image ls "$TMP_SEARCH" | awk '/^'$TMP_AWK' / { print $3 }')"
	[ -n "$TMP_IMGID" ] && return 0 || return 1
}

_getDoesDockerImageExist "$LVAR_IMAGE_NAME" "$LVAR_IMAGE_VER"
if [ $? -ne 0 ]; then
	LVAR_IMG_FULL="${LVAR_REPO_PREFIX}/$LVAR_IMG_FULL"
	_getDoesDockerImageExist "${LVAR_REPO_PREFIX}/${LVAR_IMAGE_NAME}" "$LVAR_IMAGE_VER"
	if [ $? -ne 0 ]; then
		echo "$VAR_MYNAME: Trying to pull image from repository '${LVAR_REPO_PREFIX}/'..."
		docker pull ${LVAR_IMG_FULL}
		if [ $? -ne 0 ]; then
			echo "$VAR_MYNAME: Error: could not pull image '${LVAR_IMG_FULL}'. Aborting." >/dev/stderr
			exit 1
		fi
	elif [ "$LCFG_UPDATE_REMOTE_IMAGE" = "true" ]; then
		echo "$VAR_MYNAME: Updating image from repository '${LVAR_REPO_PREFIX}/'..."
		docker pull ${LVAR_IMG_FULL} || exit 1
	fi
fi

# ----------------------------------------------------------

TMP_CONTNAME="db-mysql${TMP_IMGVER_STR}-cont"

TMP_PORT="37$(echo -n "$LVAR_IMG_VER_SHORT" | tr -d .)"

echo "Starting container '$TMP_CONTNAME' (TCP port ${TMP_PORT})..."

docker run \
		--rm \
		-d \
		-v "$VAR_MYDIR/mpdata/$OPT_IMG_VER/intern":"/var/lib/mysql" \
		-v "$VAR_MYDIR/mpdata/$OPT_IMG_VER/extern":"/root/extDbFiles" \
		-p "${TMP_PORT}:3306" \
		-e "CF_SYSUSR_MYSQL_USER_ID=$LCFG_MYSQL_USER_ID" \
		-e "CF_SYSUSR_MYSQL_GROUP_ID=$LCFG_MYSQL_GROUP_ID" \
		-e "CF_DB_ROOT_PASSWORD=$CFG_DB_ROOT_PASSWORD" \
		-e "CF_DB_USER_NAME=$CFG_DB_USER_NAME" \
		-e "CF_DB_USER_PASS=$CFG_DB_USER_PASS" \
		-e "CF_DB_SCHEME_NAME=$CFG_DB_SCHEME_NAME" \
		-e "CF_ENABLE_DB_INIT_DEBUG=$CFG_ENABLE_DB_INIT_DEBUG" \
		-e "CF_LANG=$CFG_LANG" \
		-e "CF_TIMEZONE=$CFG_TIMEZONE" \
		-e "CF_MYSQL_MAX_ALLOWED_PACKET=$CF_MYSQL_MAX_ALLOWED_PACKET" \
		-e "CF_MYSQL_INNODB_BUFFER_POOL_SIZE=$CF_MYSQL_INNODB_BUFFER_POOL_SIZE" \
		-e "CF_MYSQL_INNODB_LOG_FILE_SIZE=$CF_MYSQL_INNODB_LOG_FILE_SIZE" \
		-e "CF_MYSQL_SQLMODE=$CF_MYSQL_SQLMODE" \
		--name "$TMP_CONTNAME" \
		$LVAR_IMG_FULL
