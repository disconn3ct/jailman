#!/usr/local/bin/bash

# yml Parser function
# Based on https://gist.github.com/pkuczynski/8665367
#
# This function is very picky and complex. Ignore with shellcheck for now.
# shellcheck disable=SC2086,SC2155
parse_yaml() {
    local prefix=${2}
    local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
    sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  "${1}" |
    awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("export %s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
    }'
}

# automatic update function
gitupdate() {
    echo "checking for updates using Branch: ${1}"
    git fetch
    git update-index -q --refresh
    CHANGED=$(git diff --name-only origin/"${1}")
    if [ -n "$CHANGED" ]; then
        echo "script requires update"
        if [ "${FORCEUPDATE:-0}" -eq 1 ]; then
            echo "Set FORCEUPDATE=1 to update."
            exit 2
        fi
        git reset --hard
        git checkout "${1}"
        git pull
        echo "script updated, please restart the script manually"
        exit 1
    else
        echo "script up-to-date"
    fi
}

usage() {
    echo "Usage:"
    echo "$0 -U [BRANCH]"
    echo "    Check for jailman updates on release 'BRANCH' (dev or master)"
    echo "    Note: FORCEUPDATE environment variable must be set to 1 before"
    echo "    changes will be applied."
    echo "$0 -i [_jailname] [_jailname1] ... [_jailnameN]"
    echo "   Install jails"
    echo "$0 -r [_jailname] [_jailname1] ... [_jailnameN]"
    echo "   Reinstall jails (destroy then create)"
    echo "$0 -u [_jailname] [_jailname1] ... [_jailnameN]"
    echo "   Run jail upgrade script"
    echo "$0 -d [_jailname] [_jailname1] ... [_jailnameN]"
    echo "   Destroy jails"
    echo "$0 -g [_jailname] [_jailname1] ... [_jailnameN]"
    echo "    Update the jail and any packages inside"
    echo ""
    echo " Examples:"
    echo "   # $0 -U dev"
    echo "      Check for upgrades to jailman on the dev branch"
    echo ""
    echo "   # env FORCEUPDATE=1 $0 -U master"
    echo "      Upgrade jailman to the master branch"
    echo "      THIS WILL DESTROY ANY LOCAL CHANGES"
    echo ""
    echo "    # $0 -i plex"
    echo "      Install plex"
    echo ""
    echo "    # $0 -d plex transmission"
    echo "      Uninstall (DESTROY) plex and transmission"
}

jailcreate() {
    echo "Checking config..."
    blueprintpkgs="blueprint_${2}_pkgs"
    blueprintports="blueprint_${2}_ports"
    jailinterfaces="jail_${1}_interfaces"
    jailip4="jail_${1}_ip4_addr"
    jailgateway="jail_${1}_gateway"
    jaildhcp="jail_${1}_dhcp"
    setdhcp=${!jaildhcp}
    extraconf="${1}_extraconf"
    setextra="${!extraconf}"
    
    if [ -z "${!jailinterfaces}" ]; then
        jailinterfaces="vnet0:bridge0"
    else
        jailinterfaces=${!jailinterfaces}
    fi
    
    if [ -z "${setdhcp}" ] && [ -z "${!jailip4}" ] && [ -z "${!jailgateway}" ]; then
        echo 'no network settings specified in config.yml, defaulting to dhcp="on"'
        setdhcp="on"
    fi
    
    echo "Creating jail for $1"
    pkgs="$(sed 's/[^[:space:]]\{1,\}/"&"/g;s/ /,/g' <<<"${global_jails_pkgs:?} ${!blueprintpkgs}")"
    echo '{"pkgs":['"${pkgs}"']}' > /tmp/pkg.json
    if [ "${setdhcp}" == "on" ]
    then
        if ! iocage create -n "${1}" -p /tmp/pkg.json -r "${global_jails_version:?}" interfaces="${jailinterfaces}" dhcp="on" vnet="on" allow_raw_sockets="1" boot="on" ${setextra} -b
        then
            echo "Failed to create jail"
            exit 1
        fi
    else
        if ! iocage create -n "${1}" -p /tmp/pkg.json -r "${global_jails_version}" interfaces="${jailinterfaces}" ip4_addr="vnet0|${!jailip4}" defaultrouter="${!jailgateway}" vnet="on" allow_raw_sockets="1" boot="on" ${setextra} -b
        then
            echo "Failed to create jail"
            exit 1
        fi
    fi
    
    rm /tmp/pkg.json
    echo "creating jail config directory"
    createmount "${1}" "${global_dataset_config:?}"
    createmount "${1}" "${global_dataset_config}"/"${1}" /config
    
    # Create and Mount portsnap
    createmount "${1}" "${global_dataset_config}"/portsnap
    createmount "${1}" "${global_dataset_config}"/portsnap/db /var/db/portsnap
    createmount "${1}" "${global_dataset_config}"/portsnap/ports /usr/ports
    if [ "${!blueprintports}" == "true" ]
    then
        echo "Mounting and fetching ports"
        iocage exec "${1}" "if [ -z /usr/ports ]; then portsnap fetch extract; else portsnap auto; fi"
    else
        echo "Ports not enabled for blueprint, skipping"
    fi
    
    echo "Jail creation completed for ${1}"
    
}

# $1 = jail name
# $2 = Dataset
# $3 = Target mountpoint
# $4 = fstab prefernces
createmount() {
    if [ -z "$2" ] ; then
        echo "ERROR: No Dataset specified to create and/or mount"
        exit 1
    else
        if [ ! -d "/mnt/$2" ]; then
            echo "Dataset does not exist... Creating... $2"
            zfs create "${2}"
        else
            echo "Dataset already exists, skipping creation of $2"
        fi
        
        if [ -n "$1" ] && [ -n "$3" ]; then
            iocage exec "${1}" mkdir -p "${3}"
            if [ -n "${4}" ]; then
                iocage fstab -a "${1}" /mnt/"${2}" "${3}" "${4}"
            else
                iocage fstab -a "${1}" /mnt/"${2}" "${3}" nullfs rw 0 0
            fi
        else
            echo "No Jail Name or Mount target specified, not mounting dataset"
        fi
        
    fi
}

# $1 = jail name
# $2 = complete-mountpoint (/mnt/fetched)
# $3 = prefix ("")
# Example: createdownload myjail /mnt/fetched /kidstv
# creates ${global_dataset_downloads}/kidstv/complete and mounts to /mnt/fetched
createdownload() {
    _jailname="${1:?}"
    _mountpt="${2:?}"
    _prefix="${3:-}"
    createmount "${_jailname}" "${global_dataset_downloads:?}${_prefix}" "${_mountpt}"
    createmount "${_jailname}" "${global_dataset_downloads}${_prefix}"/complete "${_mountpt}/complete"
    createmount "${_jailname}" "${global_dataset_downloads}${_prefix}"/incomplete "${_mountpt}/incomplete"
}

# $1 = jail name
# $2 = content folder (shows, movies, etc)
# $3 = media mountpoint (/mnt/movies)
# $4 = prefix (optional)
# creates ${global_dataset_media}${prefix}/${media name} and mounts it to
# ${jail} under ${mountpoint}
# No slashes are added to or removed from prefix.
#
# Example: createmedia thisjail movies /mnt/movies /anime
# creates ${global_dataset_media}/anime/movies and mounts to /mnt/fetched
createmedia() {
    _jailname="${1:?}"
    _mediafolder="${2:?}"
    _mountpt="${3:?}"
    _prefix="${4:-}"
    # Check if dataset for media library and the dataset for content exist, create if they do not.
    createmount "${_jailname}" "${global_dataset_media:?}${_prefix}"
    createmount "${_jailname}" "${global_dataset_media}${_prefix}"/${_mediafolder}"" "${_mountpt}"
}

export -f createmount createdownload createmedia
