#!/bin/bash
#
# Copyright 2018-2021 Azul Systems Inc.  All Rights Reserved.
#
# Please contact Azul Systems, 385 Moffett Park Drive, Suite 115,
# Sunnyvale, CA 94089 USA or visit www.azul.com if you need additional
# information or have any questions.
#
# Common script utility methods v2.0
#

#echo "BASH_SOURCE ${BASH_SOURCE[@]} -- ${0}"
UTILS_SCRIPT_DIR=$(cd $(dirname "${BASH_SOURCE}") && pwd -P)
UTILS_CMD=$(readlink -f "${BASH_SOURCE}")

################################################
# Generic variables
#
APPS_DIR=${APPS_DIR:-/localhome/__SSHUSER__}
DATA_DIR=${DATA_DIR:-/localhome/__SSHUSER__}
CLIENT_DIR=${CLIENT_DIR:-/localhome/__SSHUSER__}
DIST_DIR=${DIST_DIR:-/home/$USER/dist}

PAR=${PAR:-0}
STAMP=${STAMP:-$(date -u '+%Y%m%d_%H%M%S')}
RESULTS_DIR=${RESULTS_DIR:-"$(pwd)/results_$STAMP"}

WAIT_TIME=${WAIT_TIME:-300}
USE_IPSTATS=${USE_IPSTATS:-true}
USE_TOP=${USE_TOP:-true}
USE_MPSTAT=${USE_MPSTAT:-true}
USE_DISKSTATS=${USE_DISKSTATS:-true}
CLUSTER=${CLUSTER:-false}
DROP_CACHES=${DROP_CACHES:-true}
CLEAN_DEV_SHM=${CLEAN_DEV_SHM:-true}
CLUSTER_NAME=${CLUSTER_NAME:-${BENCHMARK%-*}_perf_test}

HOSTNAME_CMD=${HOSTNAME_CMD:-"hostname -A"}
HOSTNAME=$( ${HOSTNAME_CMD} )
HOSTNAME=( ${HOSTNAME} )
HOSTNAME=$(echo ${HOSTNAME})

get_user_java() {
    if [[ -f "${JAVA_HOME}"/bin/java ]]
    then
        echo "${JAVA_HOME}"
    elif [[ -f ~/jdk_latest/bin/java ]]
    then
        echo ~/jdk_latest
    elif [[ -f ~/ws/jdk_latest/bin/java ]]
    then
        echo ~/ws/jdk_latest
    else
        echo ""
    fi
}

JAVA_HOME=${JAVA_HOME:-$(get_user_java)}
JAVA_VERSION=${JAVA_VERSION:-}
JAVA_TYPE=${JAVA_TYPE:-}
CLIENT_JAVA_HOME=${CLIENT_JAVA_HOME:-$(get_user_java)}
CLIENT_JAVA_OPTS=${CLIENT_JAVA_OPTS:-"-Xmx1g -Xms1g"}
#JAVA_OPTS_GC_LOG="-XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintGCApplicationStoppedTime -Xloggc:__DIR__/__NAME___%t.%p_gc.log"
JAVA_OPTS_GC_LOG="-XX:+PrintGCDetails -Xloggc:__DIR__/__NAME___%t.%p_gc.log"
JAVA_OPTS_GC_LOG11="-XX:+PrintGCDetails -Xloggc:__DIR__/__NAME___%t.%p_gc.log -Xlog:gc::utctime -XX:NativeMemoryTracking=summary"
JAVA_OPTS_COMP_LOG="-XX:+PrintCompilation -XX:+TraceDeoptimization -XX:+PrintCompilationStats -XX:+PrintCompileDateStamps -XX:-DisplayVMOutput -XX:+LogVMOutput -XX:LogFile=__DIR__/__NAME___%t.%p_comp.log"
JAVA_OPTS_CMS="-XX:+UseConcMarkSweepGC -XX:CMSInitiatingOccupancyFraction=75 -XX:+UseCMSInitiatingOccupancyOnly -XX:+AlwaysPreTouch"
JAVA_OPTS_G1="-XX:+UseG1GC"
JAVA_OPTS_FALCON="-XX:+UseFalcon -XX:-UseC2"
JAVA_OPTS_C2="-XX:-UseFalcon -XX:+UseC2"
RESET_INTERVAL=${RESET_INTERVAL:-300000}
RESET_ITERATIONS=${RESET_ITERATIONS:-1000}
JHICCUP_ARGS=${JHICCUP_ARGS:-"-l,__DIR__/hiccup___NAME__.%date.%pid.hlog"}

TIME_FORMAT_Z="%Y%m%dT%H%M%SZ"
LOG_PREF=""
LOG_SEP="-------------------------------------------------------------------------------"
SSH_SEP="_______________________________________________________________________________"
APP_SEP="==============================================================================="
PROP_SEP=": "

NODES_WITH_PORTS=""
NODES_IP=""
NODES_IP_WITH_PORTS=""
NUM_NODES=0

ARGS=()
NODE_OPTS=()
REMOTE_UTILS_CMD=${REMOTE_UTILS_CMD:-UTILS_CMD}

jq="${UTILS_SCRIPT_DIR}/jq"
SSH_USER=${SSH_USER:-${USER}}
SSH_EXT_ARGS=${SSH_EXT_ARGS:-"-o StrictHostKeyChecking=no -o PasswordAuthentication=no"}
SSH_KEY=${SSH_KEY:-""}
SSH_HIDE_BANNER=${SSH_HIDE_BANNER:-false}

################################################
# basic functions
#

is_true() {
    if [[ "${1}" == 1 || "${1}" == true || "${1}" == TRUE || "${1}" == yes || "${1}" == YES || "${1}" == on || "${1}" == ON ]]
    then
        return 0
    else
        return 1
    fi
}

sys_time() {
    date +%s
}

get_stamp() {
    local p=$(date -u "+%Y-%m-%d %H:%M:%S,%N")
    echo ${p::23},UTC
}

iso_time() {
    echo "$@" | sed "s|,.*||; s|\[||; s| |T|"
}

iso_time_test() {
    local p=$(get_stamp)
    echo "$p -> $(iso_time $p)"
}

log() {
    local p=
    echo "$(get_stamp) ${p}[${HOSTNAME}] [$$] ${LOG_PREF}${@}" >&2
}

logd() {
    is_true "${DEBUG}" && log "[DEBUG] $@"
}

log_sep() {
    log $LOG_SEP
}

fail() {
    log "FAILURE: ${@}"
    exit 1
}

logx() {
    local pref=${1}
    while IFS= read -r p
    do
        [[ -n "${p}" ]] && \
        log "${pref}${p}"
    done
}

log_cmd() {
    log_sep
    [[ -n "${1}" ]] && log "${1}"
    shift
    log "CMD: ${*}"
    set -o pipefail
    bash -c "${*}" |& logx '### '
    local res=$?
    set +o pipefail
    log "exit code: ${res}"
    log_sep
    return ${res}
}

sleep_for() {
    local nj=${1:-0}
    local sj
    log "Sleeping ${nj} seconds..."
    for (( sj = 0; sj < nj; sj++ ))
    do
        sleep 1
        (( (sj+1) % 10 == 0 )) && log "slept $((sj+1))..."
    done
    log "slept total $((sj))"
}

process_args() {
    while true
    do
        if [[ "${1}" == -- ]]
        then
            shift
            break
        fi
        if [[ "${1}" == DEBUG ]]
        then
            export DEBUG=true
            shift
            continue
        fi
        if [[ "${1}" == *=* ]]
        then
            [[ "${1}" == *//* && "${1}" != *"://"* ]] && break
            export "${1}"
            logd "Exported: '${1}'"
            shift
            continue
        fi
        break
    done
    local n=${#@}
    local i=1
    while (( i <= n ))
    do
        ARGS+=( "${1}" )
        (( i++ ))
        shift
    done
}

print_args() {
    local a=()
    local n=${#@}
    echo "print_args: $n"
    local i=1
    local nonempty=0
    while (( i <= n ))
    do
        [[ -n "${1}" ]] && nonempty=$i
        a+=( "${1}" )
        (( i++ ))
        shift
    done
    i=0
    while (( i < nonempty ))
    do
        echo "  args $((i+1)): ${a[i]}"
        (( i++ ))
    done
}

calc() {
    [[ -n "$bc" ]] || return 1
    local res=$(echo "${@}" | $bc)
    if echo ${res} | grep -q '\.'
    then
        echo ${res} | sed "s|[0]*$||;s|\.$||"
    else
        echo ${res}
    fi
}

check_bc() {
    if echo "1 + 2" | bc &> /dev/null
    then
        bc=bc
    else
        bc="${UTILS_SCRIPT_DIR}/bc"
    fi
    local res=$(calc "1 + 2")
    if [[ "${res}" != 3 ]]
    then
        unset bc
        fail "BC verification failed!"
    fi
}

mk_res_dir() {
    mkdir -p "${RESULTS_DIR}" || exit 1
    RESULTS_DIR=$(abs_dir "${RESULTS_DIR}")
}

mkdir_w() {
    local dir=${1}
    logd "mkdir_w '${dir}'"
    if [[ "${dir}" == *:* ]]
    then
        local rhost=${dir/:*}
        local rdir=${dir/*:}
        local rhost_ip=$(resolve_hostname "${rhost}")
        rhost_ip=${rhost_ip:-${rhost}}
        local ssh_args=${SSH_EXT_ARGS}
        [[  -n "${SSH_KEY}" ]] && ssh_args+=" -i ${SSH_KEY}"
        ssh_args+=" -l ${SSH_USER}"
        local res
        if is_true "${SSH_HIDE_BANNER}"
        then
            set -o pipefail
            {
            ssh ${ssh_args} "${rhost_ip}" <<____________EOF
            echo ${SSH_SEP}
            echo "Making remote dir '${rdir}'..."
            mkdir -p "${rdir}" || exit 1
            echo "Changing remote perms '${rdir}'..."
            chmod uga+rw "${rdir}" || exit 1
____________EOF
            } |& grep -A 100000 -- "${SSH_SEP}" |& grep -v -- "${SSH_SEP}" |& logx "  "
            res=$?
            set +o pipefail
        else
            set -o pipefail
            {
            ssh ${ssh_args} "${rhost_ip}" <<____________EOF
            echo ${SSH_SEP}
            echo "Making remote dir '${rdir}'..."
            mkdir -p "${rdir}" || exit 1
            echo "Changing remote perms '${rdir}'..."
            chmod uga+rw "${rdir}" || exit 1
____________EOF
            } |& logx "  "
            res=$?
            set +o pipefail
        fi
        return ${res}
    else
        log "Making dir '${dir}'..."
        set -o pipefail
        mkdir -p "${dir}" |& logx "  "
        local res=$?
        set +o pipefail
        (( res == 0 )) || return ${res}
        [[ "${dir}" != /* ]] && dir=${dir%%/*}
        log "Changing perms '${dir}'..."
        chmod uga+rw -R "${dir}" || return 1
        return 0
    fi
}

du_w() {
    local dir=${1}
    logd "[du_w] '${dir}'"
    if [[ "${dir}" == *:* ]]
    then
        local rhost=${dir/:*}
        local rdir=${dir/*:}
        local rhost_ip=$(resolve_hostname "${rhost}")
        rhost_ip=${rhost_ip:-${rhost}}
        local ssh_args=${SSH_EXT_ARGS}
        [[  -n "${SSH_KEY}" ]] && ssh_args+=" -i ${SSH_KEY}"
        ssh_args+=" -l ${SSH_USER}"
        ssh ${ssh_args} "${rhost_ip}" du -hs "${rdir}" | logx "  "
    else
        du -hs "${dir}" | logx "  "
    fi
}

rsync_w() {
    logd "[rsync_w] [$@]"
    local dir1=${1}
    local dir2=${2}
    local ext_opts=${3}
    local ssh_args=${SSH_EXT_ARGS}
    [[  -n "${SSH_KEY}" ]] && ssh_args+=" -i ${SSH_KEY}"
    ssh_args+=" -l ${SSH_USER}"
    if [[ "${dir1}" == *':'* ]]
    then
        local rhost1=${dir1/:*}
        local rhost_ip1=$(resolve_hostname "${rhost1}")
        rhost_ip1=${rhost_ip1:-${rhost1}}
        local rdir1=${dir1/*:}
        logd "[rsync_w] dir1 '${dir1}' -> '${SSH_USER}@${rhost_ip1}:${rdir1}'"
        dir1="${rhost_ip1}:${rdir1}"
    else
        logd "[rsync_w] dir1 '${dir1}' - unchanged"
    fi
    if [[ "${dir2}" == *':'* ]]
    then
        local rhost2=${dir2/:*}
        local rhost_ip2=$(resolve_hostname "${rhost2}")
        rhost_ip2=${rhost_ip2:-${rhost2}}
        local rdir2=${dir2/*:}
        logd "[rsync_w] dir2 '${dir2}' -> '${SSH_USER}@${rhost_ip2}:${rdir2}'"
        dir2="${rhost_ip2}:${rdir2}"
    else
        logd "[rsync_w] dir2 '${dir2}' - unchanged"
    fi
    set -o pipefail
    dir2=${dir2// /\\ }
    logd "[rsync_w] rsync -ahv ${ext_opts} '${dir1}/' '${dir2}'..."
    rsync -ahv ${ext_opts} -e "ssh ${ssh_args}" "${dir1}/" "${dir2}" | logx "  "
    local res=$?
    set +o pipefail
    return ${res}
}

sync_dirs() {
    local dir1=${1}
    local dir2=${2}
    local ext_opts=${3:-"--delete"}
    if [[ "${dir1}" != "${dir2}" ]]
    then
        local t1=$(date +%s)
        log "Syncing directory '${dir1}' to '${dir2}' ..."
        if mkdir_w "${dir2}" && rsync_w "${dir1}" "${dir2}" "${ext_opts}"
        then
            local t2=$(date +%s)
            log "  sync time: $((t2 - t1))s"
            du_w "${dir2}"
            return 0
        else
            log "Failed to sync dirs!"
            return 1
        fi
    else
        return 1
    fi
}

fetch_logs() {
    local rhost=${1}
    shift
    local rpath=${1}
    shift
    local res_dir=${1}
    shift
    local rhost_ip=$(resolve_hostname "${rhost}")
    rhost_ip=${rhost_ip:-${rhost}}
    local dirs=$(remote_simple_cmd ${rhost} ls "${rpath}")
    log "Remote dirs: '${rhost}:${rpath}/*' (${rhost_ip})..."
    mkdir -p "${res_dir}" || return 1
    echo "${dirs}" | while read dir
    do
        if [[ "${dir}" == node_* ]]
        then
            log "Fetching: '${rhost}:${rpath}/${dir}' -> '${res_dir}/${dir}'"
            rsync_w "${rhost_ip}:${rpath}/${dir}" "${res_dir}/${dir}" "--exclude data"
        else
            log "Skipping: '${rhost}:${rpath}/${dir}'"
        fi
    done
}

remote_base_cmd() {
    logd "remote_base_cmd..."
    is_true "${DEBUG}" && print_args "${@}" | logx "  "
    local rhost=${1}
    shift
    local incl_prof=${1}
    shift
    local hide_banner=${1}
    shift
    local rhost_ip=$(resolve_hostname "${rhost}")
    rhost_ip=${rhost_ip:-${rhost}}
    logd "[remote_base_cmd] '${rhost}' (${SSH_USER}@${rhost_ip}) [${@}]"
    local pn=${#@}
    local pi=0
    local args=()
    while (( pi < pn ))
    do
        args+=( "\"${1//\"/\\\"}\"" )
        shift
        (( pi++ ))
    done
    logd "[remote_base_cmd] params ${pn}, args [${args[@]}]"
    if is_true "${incl_prof}"
    then
        incl_prof=true
    else
        incl_prof=false
    fi
    local ssh_args=${SSH_EXT_ARGS}
    [[  -n "${SSH_KEY}" ]] && ssh_args+=" -i ${SSH_KEY}"
    ssh_args+=" -l ${SSH_USER}"
    local res
    if is_true "${hide_banner}"
    then
        set -o pipefail
        {
        ssh ${ssh_args} "${rhost_ip}" <<________EOF
        ${incl_prof} && source /etc/profile
        echo ${SSH_SEP}
        ${args[@]} || exit 1
________EOF
        } |& grep -A 100000 -- "${SSH_SEP}" |& grep -v -- "${SSH_SEP}" 2>&1
        res=$?
        set +o pipefail
    else
        set -o pipefail
        {
        ssh ${ssh_args} "${rhost_ip}" <<________EOF
        ${incl_prof} && source /etc/profile
        echo ${SSH_SEP}
        ${args[@]} || exit 1
________EOF
        } 2>&1
        res=$?
        set +o pipefail
    fi
    logd "[remote_base_cmd] result ${res}"
    return ${res}
}

remote_cmd() {
    local rhost=${1}
    shift
    remote_base_cmd "${rhost}" true "${SSH_HIDE_BANNER}" "${@}"
}

remote_simple_cmd() {
    local rhost=${1}
    shift
    remote_base_cmd "${rhost}" false true "${@}"
}

abs_dir() {
    local path=${1}
    [[ "${path}" != /* ]] && path=$(readlink -f "${path}")
    echo "${path}"
}

real_dir() {
    local path=${1}
    [[ "${path}" != /* || -e "${path}" ]] && path=$(readlink -f "${path}")
    echo "${path}"
}

chop() {
    local p=${1}
    echo ${p:0:${#p}-1}
}

get_dir() {
    local pdir=${1}
    local hname=${2:-${HOSTNAME}}
    local huser=${3:-${USER}}
    local hsshuser=${3:-${SSH_USER}}
    pdir="${pdir//__HOSTNAME__/${hname}}"
    pdir="${pdir//__USER__/${huser}}"
    pdir="${pdir//__SSHUSER__/${hsshuser}}"
    local par
    (( PAR > 0 )) && par="_par${PAR}"
    logd "get_dir: '${1}' -> '${pdir}${par}'"
    echo "${pdir}${par}"
}

get_data_dir() {
    get_dir "${DATA_DIR}"
}
 
get_apps_dir() {
    get_dir "${APPS_DIR}"
}

clean_dev_shm() {
    is_true "$CLEAN_DEV_SHM" || return
    log "Cleaning /dev/shm..."
    find /dev/shm -maxdepth 1 ! -name 'queue.*' ! -path /dev/shm -print -exec rm -fr {} + |& logx "### "
}

resolve_hostname() {
    local host_name=${1}
    local hosts_file=${HOSTS_FILE}
    local res
    [[ -f "${RESULTS_DIR}/hosts" ]] && hosts_file="${RESULTS_DIR}/hosts"
    if [[ -f "${hosts_file}" ]]
    then
        res=$(cat "${hosts_file}" | grep " ${host_name}$" | sed "s| ${host_name}$||")
        if [[ -n "${res}" ]]
        then
            echo ${res}
            return 0
        fi
    fi
    if res=$(host "${host_name}" | head -1)
    then
        if echo ${res} | grep -q "has address"
        then
            echo ${res} | sed "s|.* has address ||"
        elif echo ${res} | grep -q "domain name pointer"
        then
            echo ${host_name}
        fi
    else
        return 1
    fi
}

detect_hostname() {
    local ip_address=${1}
    local res
    if res=$(host "$ip_address")
    then
        if echo ${res} | grep -q "has address"
        then
            echo ${res} | sed "s| has address .*||"
        elif echo ${res} | grep -q "domain name pointer"
        then
            chop $(echo ${res} | sed "s|.* domain name pointer ||")
        fi
    else
        return 1
    fi
}

install_tools() {
    sync_dirs "${UTILS_SCRIPT_DIR}" "${1}"
}

find_artifact() {
    local name=${1}
    local dir=${2}
    local archive
    [[ -f "${archive}" ]] || archive=$(find "${src}" -name "*${name}-bin.tar.gz")
    [[ -f "${archive}" ]] || archive=$(find "${src}" -name "*${name}.tar.gz")
    [[ -f "${archive}" ]] || archive=$(find "${src}" -name "*${name}.tgz")
    [[ -f "${archive}" ]] || archive=$(find "${src}" -name "*${name}-*bin.tar.gz")
    [[ -f "${archive}" ]] || archive=$(find "${src}" -name "*${name}-*.tar.gz")
    [[ -f "${archive}" ]] || archive=$(find "${src}" -name "*${name}-*.tgz")
    [[ -f "${archive}" ]] || archive=$(find "${src}" -name "*${name}.zip")
    echo "${archive}"
}

# Install app artifact from specified source
# $1 - name of the artifact
# $2 - src of the artifact
# $3 - install dir for application, app_home -> install_dir/name
# $4 - force remove or keep already installed artifact
install_artifact() {
    local name=${1}
    local src=${2:-DIST}
    local distr=false
    if [[ "${src}" == DIST ]]
    then
        src=${DIST_DIR}
        distr=true
    elif [[ "${src}" == http* ]]
    then
        distr=true
    fi
    local install_dir=${3}
    local force_remove=${4:-true}
    if [[ -z "${name}" ]]
    then
        log "install_artifact: Missing artifact name!"
        return 1
    fi
    if [[ -z "${src}" ]]
    then
        log "install_artifact: Missing artifact source!"
        return 1
    fi
    if [[ -z "${install_dir}" ]]
    then
        log "install_artifact: Missing target install dir!"
        return 1
    fi
    local app_home="${install_dir}/${name}"
    if [[ -d "${app_home}" ]]
    then
        if is_true "${force_remove}"
        then
            log "install_artifact: Cleaning existing application dir: ${app_home}..."
            rm -fr "${app_home}" || return 1
        elif ${distr}
        then
            if [[ -f "${app_home}/INSTALLED" ]]
            then
                log "install_artifact: Using existing application dir '${app_home}' (installed previously)"
                return 0
            else
                log "install_artifact: Cleaning existing application dir '${app_home}' (installed previously)"
                rm -fr "${app_home}" || return 1
            fi
        else
            log "install_artifact: Using existing application dir '${app_home}'"
            return 0
        fi
    fi
    if [[ -d "${src}" ]]
    then
        ### from dir ###
        log "install_artifact: Looking for artifact in the dist dir '${src}'..."
        local archive=$(find_artifact "${name}" "${src}")
        if [[ -f "${archive}" ]]
        then
            src="${archive}"
        else
            log "install_artifact: Failed to find artifact '${name}' in the dist dir '${src}'!"
            return 1
        fi
    elif [[ "${src}" == http* ]]
    then
        ### from url ###
        log "install_artifact: Downloading artifact from url '${src}'..."
        mkdir -p "${install_dir}" || return 1
        wget -q -c "${src}" --directory-prefix="${install_dir}" || return 1
        local dl_name=${src/*\//}
        src="${install_dir}/${dl_name}"
    else
        ### from file ###
        log "install_artifact: artifact from file '${src}'..."
    fi
    ### from file ###
    if [[ "${src}" == *.zip ]]
    then
        log "install_artifact: Installing '${name}' from zip arch '${src}' to the app dir '${app_home}'"
        mkdir -p "${app_home}" || return 1
        if unzip "${src}" -d "${app_home}"
        then
            touch "${app_home}/INSTALLED"
            return 0
        fi
        log "install_artifact: Failed unzip '${src}'"
    else
        log "install_artifact: Installing '${name}' from tarball '${src}' to the app dir '${app_home}'"
        mkdir -p "${app_home}" || return 1
        if tar -xzf "${src}" -C "${app_home}" --strip-components=1
        then
            touch "${app_home}/INSTALLED"
            return 0
        fi
        log "install_artifact: Failed untar '${src}'"
    fi
    return 1
}

cleanup_artifacts() {
    local apphome=${1}
    log "cleanup_artifacts: '${apphome}'"
    (
    cd "${apphome}" || exit 1
    for adir in *
    do
        if [[ -f "${adir}/INSTALLED" ]]
        then
            log "cleanup_artifacts: removing installed artifact [${adir}]..."
            rm -fr "${adir}" |& logx
        elif [[ "${adir}" == node_* ]]
        then
            log "cleanup_artifacts: removing work dir [${adir}]..."
            rm -fr "${adir}" |& logx
        fi
    done
    )
}

var_java_home=""

install_java() {
    local java_name=${1}
    local src=${2}
    local install_dir=${3}
    var_java_home=""
    if [[ -f "${java_name}/bin/java" ]]
    then
        var_java_home=${java_name}
        log "install_java: using [${java_name}] as Java home"
        return 0
    fi
    #java_name=${java_name##*/}
    #java_name=${java_name%.*}
    #java_name=${java_name%-bin}
    #java_name=${java_name%.bin}
    #java_name=${java_name%-linux}
    #java_name=${java_name%.linux}
    #java_name=${java_name:-java}
    if install_artifact "${java_name}" "${src}" "${install_dir}" false
    then
        var_java_home="${install_dir}/${java_name}"
        log "install_java: installed from source [${src}] as Java home [${var_java_home}]"
        return 0
    fi
    log "install_java: failed to install Java from [${src}]!"
    return 1
}

print_disk_usage() {
    local msg=${1}
    local path=${2}
    [[ -n "${msg}" ]] && echo "${msg}"
    (
    cd "${path}" && df -h . && du -hs *
    )
}

print_free_mem() {
    free
}

print_cpu_info() {
    lscpu || cat /proc/cpuinfo
}

cat_files() {
    local path=${1}
    local p_file
    for p_file in $(ls "${path}")
    do
        if [[ -f "${path}/$p_file" ]]
        then
            echo -n "$p_file: "
            cat "${path}/$p_file"
        fi
    done
}

print_thp_info() {
    local thp_path
    if [[ -d /sys/kernel/mm/transparent_hugepage ]]
    then
        thp_path=/sys/kernel/mm/transparent_hugepage
    elif [[ -d /sys/kernel/mm/redhat_transparent_hugepage ]]
    then
        thp_path=/sys/kernel/mm/redhat_transparent_hugepage
    fi
    [[ -d "${thp_path}" ]] || return
    echo "THP path: ${thp_path}"
    cat_files ${thp_path}
}

print_sys_info() {
    {
    echo "-------------------- uname ----------------------"
    uname -a
    echo
    echo "-------------------- cpuinfo --------------------"
    print_cpu_info
    echo
    echo "-------------------- thpinfo -------------------"
    print_thp_info
    echo
    echo "-------------------- meminfo --------------------"
    cat /proc/meminfo
    echo
    print_free_mem
    echo
    echo "-------------------- zst ------------------------"
    zing-ps -s
    echo
    echo "-------------------- ulimit ---------------------"
    ulimit -a
    echo
    echo "-------------------- env ------------------------"
    env
    echo
    echo "-------------------- diskinfo -------------------"
    df -h
    echo
    echo "-------------------- lsblk -------------------"
    lsblk
    echo
    echo "-------------------- sysctl ---------------------"
    sysctl -a
    echo
    } |& cat
}

drop_caches() {
    is_true "${DROP_CACHES}" || return
    if [[ -f /home/dolphin/taskpool/bin/z_sudo ]]
    then
        log_sep
        log "----------------------------- mem before caches drop --------------------------"
        print_free_mem |& logx ''
        log_sep
        log "Dropping caches..."
        sudo -n /home/dolphin/taskpool/bin/z_sudo drop_caches > /dev/null || return 1
        log "----------------------------- mem after caches drop ---------------------------"
        print_free_mem |& logx ''
        log_sep
    else
        log "Cannot drop caches: no z_sudo found"
        log_sep
        log "----------------------------- mem                    --------------------------"
        print_free_mem |& logx ''
    fi
}

find_process() {
    local pars="-u $(whoami)"
    local p
    while [[ "${1}" == -* ]]
    do
        pars="${pars} ${1}"
        shift
    done
    local args="${@}"
    pgrep ${pars} "${args}"
}

check_process() {
    local pars="-u $(whoami)"
    local p
    while [[ "${1}" == -* ]]
    do
        pars="${pars} ${1}"
        shift
    done
    local args="${@}"
    log "pgrep args: ${pars} '${args}'"
    if p=$(pgrep ${pars} "${args}")
    then
        log "Found process: ${pars} '${args}' - ${p}..."
        return 0
    else
        return 1
    fi
}

stop_process() {
    local pars="-u $(whoami)"
    local p
    while [[ "${1}" == -* ]]
    do
        pars="${pars} ${1}"
        shift
    done
    local args="${@}"
    log "pgrep args: ${pars} '${args}'"
    if p=$(pgrep ${pars} "${args}")
    then
        log "Killing ${pars} '${args}' - ${p}..."
        pkill ${pars} "${args}"
    fi
    for (( i = 0; i < 30; i++ ))
    do
        p=$(pgrep ${pars} "${args}") || break
        sleep 1
    done
    if p=$(pgrep ${pars} "${args}")
    then
        log "Force killing (--signal 9) ${pars} '${args}' - ${p}..."
        pkill -9 ${pars} "${args}"
        for (( i = 0; i < 30; i++ ))
        do
            if p=$(pgrep ${pars} "${args}")
            then
                sleep 1
            else
                break
            fi
        done
    fi
    if p=$(pgrep ${pars} "${args}")
    then
        log "WARNING: Process(es) still alive ${pars} '${args}' - ${p}..."
    fi
}

wait_for_app_start() {
    local name=${1}
    local log=${2}
    local msg=${3}
    local check_log=${4:-true}
    local wait_time=${5:-${WAIT_TIME:-600}}
    for (( i = 0; i <= wait_time; i += 5 ))
    do
        if is_true "${check_log}"
        then
            check_jvm_log "${log}" || return 1
        fi
        if cat "${log}" | grep "${msg}"
        then
            log "${name} started"
            break
        elif (( i < wait_time ))
        then
            log "Waiting for ${name} to start (${i}/${wait_time})..."
            sleep 5
        else
            log "Failed to start ${name}"
            return 1
        fi
    done
    return 0
}

start_ipstats() {
    is_true "${USE_IPSTATS}" || return
    local output=${1:-$(pwd)/ipstat.log}
    local hname=${2:-${HOSTNAME}}
    local delay=5
    bash "${UTILS_SCRIPT_DIR}/ipstats.sh" "${delay}" "${hname}" &> "${output}" &
    log "Started IP stats"
}

start_top() {
    is_true "${USE_TOP}" || return
    local output=${1:-$(pwd)/top.log}
    local hname=${2:-${HOSTNAME}}
    local delay=5
    local start=$(get_stamp)
    log "Starting top..."
    {
    echo "DELAY: ${delay}"
    echo "START: ${start}"
    echo "HOST: ${hname}"
    echo
    top -i -c -b -d ${delay} -w 512
    } &> "${output}" &
    local top_pid=$!
    sleep 1
    if grep "unknown argument 'w'" "${output}"
    then
        kill $top_pid # make sure
        {
        echo "DELAY: ${delay}"
        echo "START: ${start}"
        echo "HOST: ${hname}"
        echo
        top -i -c -b -d ${delay}
        } &> "${output}" &
    fi
    log "Started top"
}

start_mpstat() {
    is_true "${USE_MPSTAT}" || return
    local output=${1:-$(pwd)/mpstat.log}
    local hname=${2:-${HOSTNAME}}
    local delay=5
    local start=$(get_stamp)
    log "Starting mpstat..."
    {
    echo "DELAY: ${delay}"
    echo "START: ${start}"
    echo "HOST: ${hname}"
    echo
    mpstat -P ALL ${delay}
    } &> "${output}" &
    log "Started mpstat"
}

start_diskstats() {
    is_true "${USE_DISKSTATS}" || return
    local output=${1:-$(pwd)/diskstat.log}
    local hname=${2:-${HOSTNAME}}
    local delay=5
    local start=$(get_stamp)
    log "Starting sar for disk stats..."
    {
    echo "DELAY: ${delay}"
    echo "START: ${start}"
    echo "HOST: ${hname}"
    echo
    sar -d -p ${delay}
    } &> "${output}" &
    log "Started sar"
}

start_custom_scripts() {
    [[ -n "${CUSTOM_SCRIPT}" ]] || return
    local p=${CUSTOM_SCRIPT}
    p=${p##*/}
    p=${p%.*}
    log "Starting custom script: ${CUSTOM_SCRIPT}..."
    "${CUSTOM_SCRIPT}"  &> "${1}/${p}.log" &
    log "Started custom script"
}

stop_custom_scripts() {
    [[ -n "${CUSTOM_SCRIPT}" ]] || return
    stop_process -f "^${CUSTOM_SCRIPT}$"
}

check_monitors() {
    if check_process top || \
       check_process sar || \
       check_process -f ipstats.sh
    then
        return 0
    else
        return 1
    fi
}

start_monitor_tools() {
	local out_dir=${1}
	print_sys_info > "${out_dir}/system_info1.log"
    start_top "${out_dir}/top.log"
    start_mpstat "${out_dir}/mpstat.log"
    start_ipstats "${out_dir}/ipstat.log"
    start_diskstats "${out_dir}/diskstat.log"
    start_custom_scripts "${out_dir}"
}

stop_monitor_tools() {
	local out_dir=${1}
    is_true "${USE_TOP}" && stop_process top
    is_true "${USE_MPSTAT}" && stop_process mpstat
    is_true "${USE_DISKSTATS}" && stop_process sar
    is_true "${USE_IPSTATS}" && stop_process -f ipstats.sh
    stop_custom_scripts
}

wait_for_port() {
    local port=${1}
    local name=${2}
    local times_cnt=0
    local times_max=${3:-20}
    log "Waiting for ${name}..."
    while ! netstat -lnt | grep -q ${port}
    do
        (( times_cnt++ ))
        if (( times_cnt == times_max ))
        then
            log "Failed to start ${name}!"
            return 1
        fi
        log "Waiting for ${name} on port ${port} (${times_cnt} retry of 10)"
        sleep 2
    done
    log "${name} started on port ${port}"
}

################################################
# 'node' helper functions
#

host_cmd() {
    print_args "${@}"
    local rhost=${1}
    rhost=${rhost/:*}
    shift
    if [[ "${rhost}" == localhost ]]
    then
        log "Local command: '${@}'"
        "${@}"
    else
        remote_cmd "${rhost}" "${@}"
    fi
}

tools_cmd() {
    local host=${1}
    shift
    host_cmd "${host}" "${REMOTE_UTILS_CMD}" "${@}"
}

node_cmd() {
    logd "node_cmd..."
    is_true "${DEBUG}" && print_args "${@}" | logx "  "
    local func=${1}
    shift
    local node=${1}
    shift
    local node_num=${1}
    shift
    local rhost=${node/:*}
    if [[ "${rhost}" == localhost ]]
    then
        ${func} ${node} ${node_num} "${@}"
    else
        remote_cmd "${rhost}" "${REMOTE_UTILS_CMD}" \
        "DEBUG=${DEBUG}" "HOSTS_FILE=${HOSTS_FILE}" "SSH_USER=${SSH_USER}" \
        "APPS_DIR=${APPS_DIR}" "DATA_DIR=${DATA_DIR}" "APP_NAME=${APP_NAME}" \
        "DIST_DIR=${DIST_DIR}" "PAR=${PAR}" "${NODE_OPTS[@]}" \
        ${func} ${node} ${node_num} "${@}"
    fi
    local res=$?
    logd "node_cmd res: ${res}"
    return ${res}
}

var_nodes=()

_IS_NUMBER='^[0-9]+$'

print_nodes() {
    local nodes="${@:-localhost}"
    echo ${nodes//,/ }
}

print_nodes_hosts() {
    local nodes=( $( print_nodes ${NODES} ) )
    local node
    local hosts=()
    local host
    local rhost
    local found
    for node in "${nodes[@]}"
    do
        rhost=${node/:*}
        found=false
        for host in "${hosts[@]}"
        do
            if [[ "${rhost}" == "${host}" ]]
            then
                found=true
                break
            fi
            ${found} || hosts+=( "${rhost}" )
        done
    done
}

get_node_from_param() {
    local node=${1}
    if [[ "${node}" == LAST_NODE || "${node}" =~ $_IS_NUMBER ]]
    then
        local nodes=( $( print_nodes ${NODES} ) )
        local node_count=${#nodes[@]}
        local idx=$((node_count - 1))
        if [[ "${node}" == LAST_NODE ]]
        then
            idx=$((node_count - 1))
        else
            idx=${node}
        fi
        node=${nodes[idx]}
    fi
    echo -n "$node"
}

is_first_node() {
    local idx=${1}
    local is_first=true
    local nodes=( $( print_nodes ${NODES} ) )
    local node=${nodes[idx]}
    local node_host=${node%:*}
    local ii=0
    while (( ii < idx ))
    do
        local node0=${nodes[ii]}
        local node0_host=${node0%:*}
        [[ "${node0_host}" == "${node_host}" ]] && is_first=false
        (( ii++ ))
    done
    echo -n $is_first
}

get_node_count() {
    local nodes=( $( print_nodes ${NODES} ) )
    echo -n ${#nodes[@]}
}

get_node_name() {
    local idx=${1}
    local nodes=( $( print_nodes ${NODES} ) )
    local node=${nodes[idx]}
    local node_name=${node/:/_}
    echo -n "${node_name}"
}

get_node_host() {
    local idx=${1}
    local nodes=( $( print_nodes ${NODES} ) )
    local node=${nodes[idx]}
    local rhost=${node/:*}
    echo -n "${rhost}"
}

get_master_node() {
    local resolve=${1}
    local nodes=( $( print_nodes ${NODES} ) )
    local res=${nodes[0]}
    is_true "${resolve}" && res=$(resolve_hostname "${res}")
    echo ${res}
}

declare -A DEFAULT_PORTS
DEFAULT_PORTS[kafka]=0
DEFAULT_PORTS[cassandra]=0
DEFAULT_PORTS[elasticsearch]=9200

parse_nodes() {
    if (( NUM_NODES > 0 ))
    then
        logd "Parse nodes: ${NODES:-localhost} - already parsed $NUM_NODES"
        return
    fi
    log "Parse nodes: ${NODES:-localhost}..."
    local app_name=${1}
    local app_name_lc=${app_name,,}
    NODES_WITH_PORTS=""
    NODES_IP=""
    NODES_IP_WITH_PORTS=""
    local res=0
    local node
    if [[ -n "$NODES" ]]
    then
        var_nodes=( $( print_nodes ${NODES} ) )
        NUM_NODES="${#var_nodes[@]}"
        log "  master node: ${var_nodes[0]}"
        log "  num nodes: $NUM_NODES"
        for node in "${var_nodes[@]}"
        do
            local node_host=${node%:*}
            node_ip=$(resolve_hostname "$node_host")
            log "  node $node, IP: $node_ip"
            if [[ -n "$NODES_WITH_PORTS" ]]
            then
                NODES_WITH_PORTS="${NODES_WITH_PORTS},"
                NODES_IP="${NODES_IP},"
                NODES_IP_WITH_PORTS="${NODES_IP_WITH_PORTS},"
            fi
            local port=${DEFAULT_PORTS[$app_name_lc]}
            [[ "${node}" == *:* ]] && port=${node#*:}
            NODES_WITH_PORTS="${NODES_WITH_PORTS}${node}:${port}"
            NODES_IP="${NODES_IP}${node_ip}"
            NODES_IP_WITH_PORTS="${NODES_IP_WITH_PORTS}${node_ip}:${port}"
        done
    else
        var_nodes=( localhost )
        NUM_NODES=1
        local port=${DEFAULT_PORTS[$app_name_lc]}
        NODES_WITH_PORTS="localhost:${port}"
        NODES_IP="127.0.0.1"
        NODES_IP_WITH_PORTS="127.0.0.1:${port}"
        log "  master node: localhost"
        log "  num nodes: $NUM_NODES"
    fi
    log "Parse nodes done: $NUM_NODES -> ${var_nodes[@]}"
    return ${res}
}

# nodes function method
# $1 - node list
# $2 - stop loop during error on current command
# $3 - node command
nodes_func() {
    logd "[nodes_func] ==============================================="
    logd "[nodes_func] ${@}"
    local cmd=${1}
    shift
    local nodes=${1}
    shift
    local stop_on_error=${1}
    shift
    local res=0
    local node
    nodes=( $( print_nodes "${nodes}" ) )
    local n=${#nodes[@]}
    logd "[nodes_func] ${n} nodes - ${nodes[@]}"
    local node_num=0
    local node
    for node in "${nodes[@]}"
    do
        (( node_num++ ))
        local str="${cmd} [${node}] [${node_num}] [${@}]"
        logd "[nodes_func] node #${node_num}: ${str}"
        if ! ${cmd} "${node}" "${node_num}" "${@}"
        then
            res=1
            if is_true "${stop_on_error}"
            then
                log "[nodes_func] failed to ${str} - stopping!"
                break
            else
                log "[nodes_func] failed to ${str}!"
            fi
        fi
    done
    return ${res}
}

# nodes remote operations method
# $1 - node list
# $2 - stop loop during error on current command
# $3 - node command
nodes_cmd() {
    logd "[nodes_cmd] ==============================================="
    logd "[nodes_cmd] ${@}"
    local cmd=${1}
    shift
    local nodes=${1}
    shift
    local stop_on_error=${1}
    shift
    local res=0
    local node
    nodes=( $( print_nodes "${nodes}" ) )
    local n=${#nodes[@]}
    logd "[nodes_cmd] ${n} nodes - ${nodes[@]}"
    local node_num=0
    local node
    for node in "${nodes[@]}"
    do
        (( node_num++ ))
        local str="node_cmd [${cmd}] [${node}] [${node_num}] [${@}]"
        logd "[nodes_cmd] node #${node_num}: ${str}"
        if ! node_cmd ${cmd} "${node}" "${node_num}" "${@}"
        then
            res=1
            if is_true "${stop_on_error}"
            then
                log "[nodes_cmd] failed to ${str} - stopping!"
                break
            else
                log "[nodes_cmd] failed to ${str}!"
            fi
        fi
    done
    return ${res}
}

################################################
# results processing
#

detect_config() {
    local java="${1}/bin/java"
    local opts=${2}
    local config=""
    if echo "${opts}" | grep -q -- "-XX:+UseFalcon" && echo "${opts}" | grep -q -- "-XX:-UseC2"
    then
        config="falcon"
    elif echo "${opts}" | grep -q -- "-XX:-UseFalcon" && echo "${opts}" | grep -q -- "-XX:+UseC2"
    then
        config="cc2"
    fi
    if echo "${opts}" | grep -q -- "-Xmx"
    then
        local heap=$(echo ${opts} | sed "s|.*-Xmx||;s| .*||;s|g||")
        config="${config} heap${heap}"
    fi
    if echo "${opts}" | grep -q -- "-XX:ProfileLogIn="
    then
        config="${config} profile-in"
    fi
    if echo "${opts}" | grep -q -- "-XX:ProfileLogOut="
    then
        config="${config} profile-out"
    fi
    if echo "${opts}" | grep -q -- "-XX:+ProfilePrintReport"
    then
        config="${config} profile-print"
    fi
    if echo "${opts}" | grep -q -- "-XX:+UseG1GC"
    then
        config="${config} g1"
    fi
    if echo "${opts}" | grep -q -- "-XX:+UseConcMarkSweepGC"
    then
        config="${config} cms"
    fi
    if echo "${opts}" | grep -q -- "-XX:+UseZGC"
    then
        config="${config} zgc"
    fi
    if echo "${opts}" | grep -q -- "-XX:+UseShenandoahGC"
    then
        config="${config} shenandoah"
    fi
    if echo "${opts}" | grep -q -- "-XX:+BestEffortElasticity"
    then
        config="${config} bee"
    fi
    if [[ -n "${NODES}" ]]
    then
        config="${config} nodes_${NODES}"
    fi
    echo ${config} ${CONFIG}
}

detect_java_version() {
    local java="${1:-${JAVA_HOME}}/bin/java"
    local ver=$($java -version 2>&1 | grep "java version" | sed 's|java version||; s|"||g')
    ver=($ver)
    if [[ "$ver" == 11* ]]
    then
        echo 11
    elif [[ "$ver" == 1.8.* ]]
    then
        echo 8
    fi
}

detect_vm_type() {
    local java="${1:-${JAVA_HOME}}/bin/java"
    local opts=$2
    local p=$($java -version 2>&1)
    if [[ "${p,,}" == *zing* ]]
    then
        echo zing
    elif [[ "${p,,}" == *zulu* ]]
    then
        echo zulu
    elif [[ "${p,,}" == *hotspot* ]]
    then
        echo oracle
    elif [[ "${p,,}" == *openjdk* ]]
    then
        echo openjdk
    elif [[ "${java,,}" == *zing* ]]
    then
        echo zing
    elif [[ "${java,,}" == *zulu* ]]
    then
        echo zulu
    elif [[ "${java,,}" == *openjdk* ]]
    then
        echo openjdk
    else
        echo unknown
    fi
}

detect_vm_build() {
    local java_home=${1}
    if echo "${java_home}" | grep -q -- "zvm-dev-"
    then
        echo "${java_home}" | sed "s|.*zvm-dev-||; s|/.*||"
    elif echo "${java_home}" | grep -q -- "zvm-"
    then
        echo "${java_home}" | sed "s|.*zvm-||; s|/.*||"
    elif echo "${java_home}" | grep -q -- "/j2sdk/"
    then
        echo "${java_home}" | sed "s|.*/j2sdk/||; s|/.*||"
    elif echo "${java_home}" | grep -q -- "/jdk"
    then
        echo "${java_home}" | sed "s|.*/jdk||; s|/.*||"
    else
        basename "${java_home}"
    fi
}

detect_os_name() {
    if [[ -f /etc/system-release ]]
    then
        cat /etc/system-release
    elif [[ -f /etc/os-release ]]
    then
        local name=$(cat /etc/os-release | grep '^NAME="' | sed 's|^NAME="||; s|"||')
        local version=$(cat /etc/os-release | grep '^VERSION="' | sed 's|^VERSION="||; s|"||')
        echo ${name} ${version}
    else
        echo Unknown
    fi
}

check_jvm_log() {
    local f=${1}
    if tail -10 "$f" | grep -q "Could not create the Java Virtual Machine\|There is insufficient memory\|Error occurred during initialization of VM\|Unable to find java executable" || \
       tail -10 "$f" | grep -q "Hard stop enforced\|Zing VM Error\|java does not meet this requirement\|Could not create the Java Virtual Machine\|Failed to fund AC"
    then
        log "Failed to start JVM. Following error has been reported:"
        echo ${LOG_SEP}
        tail -10 "$f"
        echo ${LOG_SEP}
        return 1
    else
        return 0
    fi
}

create_run_properties() {
    local res_dir=${1:-$(pwd)}
    local use_log=${2:-false}
    local log_dir=${3:-${res_dir}}
    local res_dir_abs=$(cd "${res_dir}"; pwd)
    logd "Results dir: ${res_dir}_abs"

    local blog=$(find "$log_dir" -name "run-benchmark.log*")
    local time_file="${res_dir}/time_out.log"
    local rally_out=$(find "${res_dir}" -name "rally_out_*.log*")
    [[ -f "${rally_out}" ]] || rally_out=$(find "${res_dir}" -name "rally.log*")
    local zookeeper_out=$(find "${res_dir}" -name "zookeeper_server_out.log*")
    local props="${res_dir}/run.properties.json"

    local start_time
    local finish_time
    local config
    local hst
    local build
    local build_type
    local vm_type
    local benchmark
    local workload
    local workload_name
    local workload_parameters
    local vm_home
    local vm_args
    local vm_ver
    local client_vm_home
    local client_vm_args
    local application
    local os
    local update_times=true

    if [[ ! -f "${time_file}" ]]
    then
        [[ -f "${rally_out}" ]] && time_file="${rally_out}"
        [[ -f "${zookeeper_out}" ]] && time_file="${zookeeper_out}"
    fi

    if [[ -f "${time_file}" ]]
    then
        log "Using time file: ${time_file}"
        start_time=$(iso_time $(head -1 "${time_file}"))
        finish_time=$(iso_time $(tail -1 "${time_file}"))
    elif [[ -e "$ORIG_FILE" ]]
    then
        local file_time=$(stat -c %y "$ORIG_FILE")
        log "Using orig file time: $ORIG_FILE -> ${file_time}"
        start_time=$(date "+$TIME_FORMAT_Z" -d "${}file_time}")
    else
        local stamp=$(get_stamp)
        log "Using stamp time: $stamp"
        start_time=$(iso_time $stamp)
        grep start_time "${props}" && update_times=false
    fi

    if [[ -f "${props}" ]]
    then
        log "Updating existing props file results dir..."
        sed -i "s|\"results_dir\".*:.*\".*\"|\"results_dir\": \"${res_dir_abs}\"|" "${props}"
        if $update_times
        then
            log "Updating existing props file times..."
            sed -i "s|\"start_time\".*:.*\".*\"|\"start_time\": \"${start_time}\"|" "${props}"
            sed -i "s|\"finish_time\".*:.*\".*\"|\"finish_time\": \"${finish_time}\"|" "${props}"
        fi
        cat "${props}"
        return
    fi

    if [[ -f "${blog}" ]]
    then
        log "Filling basic properties from benchmark log: ${blog}"
        config=$(echo $(cat "${blog}" | grep 'CONFIG:' | sed -e "s|CONFIG:||"))
        build=$(echo $(cat "${blog}" | grep 'BUILD_NO:' | sed -e "s|BUILD_NO:||"))
        build_type=$(echo $(cat "${blog}" | grep 'BUILD_TYPE:' | sed -e "s|BUILD_TYPE:||"))
        vm_type=$(echo $(cat "${blog}" | grep 'VM_TYPE:' | sed -e "s|VM_TYPE:||"))
        vm_ver=$(echo $(cat "${blog}" | grep 'JDK_VERSION:' | sed -e "s|JDK_VERSION:||"))
    fi

    if [[ "${use_log}" == true ]] && [[ -f "${blog}" ]]
    then
        log "Getting run properties from benchmark log..."
        hst=$(echo $(cat "${blog}" | grep 'HOST:' | sed -e "s|HOST:||"))
        benchmark=$(echo $(cat "${blog}" | grep 'BENCHMARK:' | sed -e "s|BENCHMARK:||"))
        workload=$(echo $(cat "${blog}" | grep 'WORKLOAD:' | sed -e "s|WORKLOAD:||"))
        workload_name=$(echo $(cat "${blog}" | grep 'WORKLOAD_NAME:' | sed -e "s|WORKLOAD_NAME:||"))
        workload_parameters=$(echo $(cat "${blog}" | grep 'WORKLOAD_PARAMETERS:' | sed -e "s|WORKLOAD_PARAMETERS:||"))
        vm_home=$(echo $(cat "${blog}" | grep 'JAVA_HOME:' | sed -e "s|JAVA_HOME:||"))
        vm_args=$(echo $(cat "${blog}" | grep 'VM_ARGS:' | sed -e "s|VM_ARGS:||"))
    elif [[ "${use_log}" != true ]]
    then
        log "Creating run properties..."
        if [[ ! -f "${blog}" ]]
        then
            config=$(detect_config "${JAVA_HOME}" "${JAVA_OPTS}")
            build=$(detect_vm_build "${JAVA_HOME}")
            init_java_type
            vm_type=${JAVA_TYPE}
            vm_ver=${JAVA_VERSION}
        fi
        hst=${HOSTNAME}
        os=$(detect_os_name)
        application=${APP_NAME}
        benchmark=${BENCHMARK}
        workload=${BENCHMARK_WORKLOAD}
        [[ -n "${BENCHMARK_PARAMETERS}" ]] && workload="${workload}//${BENCHMARK_PARAMETERS}"
        workload_name=${BENCHMARK_WORKLOAD}
        workload_parameters=${BENCHMARK_PARAMETERS}
        vm_home=${JAVA_HOME}
        vm_args=${JAVA_OPTS}
        client_vm_home=${CLIENT_JAVA_HOME}
        client_vm_args=${CLIENT_JAVA_OPTS}
    else
        log "Skipped creating run properties"
        return 1
    fi

    cat<<EOF > "${props}"
{ "doc" : { "run_properties": {
  "config": "${config}",
  "host": "$hst",
  "build": "$build",
  "build_type": "$build_type",
  "vm_type": "$vm_type",
  "vm_home": "$vm_home",
  "vm_args": "$vm_args",
  "vm_version": "$vm_ver",
  "client_vm_home": "$client_vm_home",
  "client_vm_args": "$client_vm_args",
  "os": "$os",
  "application": "$application",
  "benchmark": "$benchmark",
  "workload": "$workload",
  "workload_name": "$workload_name",
  "workload_parameters" : "$workload_parameters",
  "results_dir": "$res_dir_abs",
  "start_time": "$start_time",
  "finish_time": "$finish_time"
}}}
EOF

    log "Run properties created:"
    chmod a+w "${props}"
    cat "${props}"
}

workload_list() {
    local base_dir=${1}
    local function=${2}
    local workloads=${3}
    local workloads_list
    local args
    if echo "${workloads}" | grep -q '//'
    then
        args=$(echo ${workloads} | sed "s|.*//||")
        workloads=$(echo ${workloads} | sed "s|//.*||")
    fi
    if [[ -f "${workloads}" || -f "${base_dir}/lists/${workloads}" ]]
    then
        if [[ -f "${workloads}" ]]
        then
            workloads_list=$(cat "${workloads}")
            log "Running workloads: $(echo ${workloads_list}) (${args}) from file list: ${workloads}"
        else
            workloads_list=$(cat "${base_dir}/lists/${workloads}")
            log "Running workloads: $(echo ${workloads_list}) (${args}) from file list: ${base_dir}/lists/${workloads}"
        fi
    else
        workloads_list=${workloads}
        log "Running workloads: $(echo ${workloads_list}) (${args})"
    fi
    local w
    for w in ${workloads_list}
    do
        $function "${w}" "${args}"
    done
}

write_score_on() {
    local score_file=${1}; shift
    local name=${1}; shift
    local scale=${1}; shift
    local score=${1}; shift
    name=${name/ /_}
    name=${name/ /_}
    name=${name/ /_}
    echo "Score on ${name}: ${score} ${scale}"
    [[ -n "${score_file}" ]] || return
    echo "Score on ${name}: ${score} ${scale}" >> "${score_file}"
}

write_score_json() {
    local score_json=${1}; shift
    local name=${1}; shift
    local scale=${1}; shift
    local score=${1}; shift
    local step=${1}; shift
    local host=${1}; shift
    local start=${1}; shift
    local finish=${1}; shift
    [[ -n "${score_json}" ]] || return
    if [[ -f "${score_json}" ]] 
    then
        sed -i '$ d' "${score_json}"
        echo -n "}," >> "${score_json}"
    else
        echo -n '{ "doc": { "scores": [ ' > "${score_json}"
    fi
    cat<<EOF >> "${score_json}"
{
  "name": "$name",
  "unit": "$scale",
  "value": $score,
  "host": "$host",
  "step": $step,
  "duration": $((finish - start)),
  "start": $start,
  "end":   $finish
} ]}}
EOF
}

write_score() {
    write_score_on "$1" "$3" "$4" "$5"
    write_score_json "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
}

list_args() {
    echo --------------------
    for arg in "${@}"
    do
        echo "[$arg]"
    done
    echo --------------------
}

declare -A var_arg_list

init_arg_list() {
    local args=${1}
    local k
    for k in "${!var_arg_list[@]}"
    do
        unset var_arg_list[$k]
    done
    local p=( ${args//,/ } )
    local n=${#p[@]}
    local q
    IFS='='
    for (( i = 0; i < n; i++ ))
    do
        q=( ${p[i]} )
        local pname=${q[0]}
        local pvalue=${q[1]}
        log "  Parsed arg: ${pname} = ${pvalue}"
        var_arg_list[$pname]=${pvalue}
    done
    unset IFS
}

get_arg() {
    local key=${1}
    local defval=${2}
    local val=${var_arg_list[$key]}
    if [[ -n "${val}" ]]
    then
        log "  Param: ${key} - ${var_arg_list[$key]}" >&2
    else
        val=${defval}
        log "  Param: ${key} - ${defval} (default)" >&2
    fi
    echo ${val}
}

init_workload_name() {
    local wl=${1}
    if echo "${wl}" | grep -q '//'
    then
        wl=$(echo ${wl} | sed "s|//.*||")
    fi
    BENCHMARK_WORKLOAD=${wl}
}

init_workload_args() {
    local args=${1}
    if echo "${args}" | grep -q '//'
    then
        args=$(echo ${args} | sed "s|.*//||")
    else
        args=""
    fi
    BENCHMARK_PARAMETERS=${args}
    init_arg_list "${args}"
}

make_dist() {
    local copy=${1}; shift
    local app=${1}; shift
    local dist=${1}; shift
    rm -f ${app}.zip || exit 1
    zip -r ${app}.zip "${@}" || exit 1
    chmod 444 ${app}.zip
    if is_true "${copy}"
    then
        if [[ -f "${dist}/${app}.zip" ]]
        then
            i=0
            while [[ -f "${dist}/${app}.zip.${i}" ]] && (( i < 100 ))
            do
                (( i++ ))
            done
            mv -fv "${dist}/${app}.zip" "${dist}/${app}.zip.${i}"
        fi
        cp -fv ${app}.zip "${dist}" || exit 1
    fi
}

init_java_opts() {
    local java_opts
    java_opts=$(echo "${JAVA_OPTS}" | sed "s|__G1__|${JAVA_OPTS_G1}|g;  s|__CMS__|${JAVA_OPTS_CMS}|g;  s|__FALCON__|${JAVA_OPTS_FALCON}|; s|__C2__|${JAVA_OPTS_C2}|; ")
    JAVA_OPTS=${java_opts}
}

init_java_type() {
    [[ -n "${JAVA_VERSION}" ]] || JAVA_VERSION=$(detect_java_version "${JAVA_HOME}")
    [[ -n "${JAVA_TYPE}" ]] || JAVA_TYPE=$(detect_vm_type "${JAVA_HOME}")
}

preprocess_java_opts() {
    init_java_type
    local java_opts=${1}
    local dir=${2}
    local name=${3}
    local host=${4:-${HOSTNAME}}
    local script_dir=${5:-${UTILS_SCRIPT_DIR}}
    local hargs
    [[ -n "${JHICCUP_ARGS}" ]] && hargs="=${JHICCUP_ARGS}"
    local gcargs
##    if (( JAVA_VERSION > 8 )) && [[ "${JAVA_TYPE}" != zing* ]]
##    then
##        gcargs=${JAVA_OPTS_GC_LOG11}
##    else
        gcargs=${JAVA_OPTS_GC_LOG}
##    fi
    java_opts=$(echo "${java_opts}" | sed "s|__G1__|${JAVA_OPTS_G1}|g;  s|__CMS__|${JAVA_OPTS_CMS}|g;  s|__FALCON__|${JAVA_OPTS_FALCON}|; s|__C2__|${JAVA_OPTS_C2}|; ")
    java_opts=$(echo "${java_opts}" | sed "s|__LOGGC__|${gcargs}|g;  s|__LOGCOMP__|${JAVA_OPTS_COMP_LOG}|g; ")
    java_opts=$(echo "${java_opts}" | sed "s|__GC_LOG__|__DIR__/__NAME___%t.%p_gc.log|g")
    java_opts=$(echo "${java_opts}" | sed "s|__JHICCUP__|-javaagent:${script_dir}/jHiccup.jar${hargs}|g")
    java_opts=$(echo "${java_opts}" | sed "s|__RESET__|-javaagent:${script_dir}/reset-agent.jar=terminateVM=false,timeinterval=${RESET_INTERVAL},iterations=${RESET_ITERATIONS}|g")
    java_opts=$(echo "${java_opts}" | sed "s|__DIR__|${dir}|g")
    java_opts=$(echo "${java_opts}" | sed "s|__NAME__|${name}|g")
    java_opts=$(echo "${java_opts}" | sed "s|__HOST__|${host}|g")
    java_opts=$(echo "${java_opts}" | sed "s|__STAMP__|${STAMP}|g")
    java_opts=$(echo "${java_opts}" | sed "s|__USER__|${USER}|g")
    java_opts=$(echo "${java_opts}" | sed "s|__SSHUSER__|${SSH_USER}|g")
    java_opts=$(echo "${java_opts}" | sed "s|__HOSTNAME__|${HOSTNAME}|g")
    java_opts=$(echo "${java_opts}" | sed "s|^\s*||")
    echo "${java_opts}"
}

get_java_opts() {
    init_java_opts
    local dir=${1}
    local name=${2}
    local host=${3}
    local script_dir=${4}
    preprocess_java_opts "${JAVA_OPTS} ${JAVA_BASE_OPTS}" "${dir}" "${name}" "${host}" "${script_dir}"
}

exclude_java_mem() {
    echo "${@} " | sed "s|-Xmx[^ ]*||"
}

get_java_mem() {
    echo "${@} " | grep -q -- "-Xmx" && echo "${@} " | sed "s|.*-Xmx||; s| .*||"
}

set_property() {
    local file=${1}
    local prop=${2}
    local value=${3}
    local sep=${4:-${PROP_SEP}}
    local currValue=$(grep -- "^${prop}${sep}\|# ${prop}${sep}" "${file}")
    if [[ -z "${currValue}" ]]
    then
        log "set_property: appending '${prop}${sep}${value}'"
        echo >> "${file}"
        echo "$prop${sep}$value" >> "${file}"
    elif [[ "$currValue" == "# "* ]]
    then
        log "set_property: uncommenting '${currValue}' -> '${prop}${sep}${value}'"
        sed --in-place "s|# \(\b${prop}\b\)${sep}.*|\1${sep}${value}|" "${file}"
    else
        log "set_property: changing '${currValue}' -> '${prop}${sep}${value}'"
        sed --in-place "s|\(.*\b${prop}\b\)${sep}.*|\1${sep}${value}|" "${file}"
    fi
}

set_property_s() {
    local file=${1}
    local prop=${2}
    local value=${3}
    local sep=${4:-': '}
    sed --in-place "s|\(.*$prop\)${sep}.*|\1${sep}$value|" "${file}"
}

set_properties() {
    local props=${1}
    local prop_file=${2}
    local node_num=${3}
    if [[ -n "${props}" ]]
    then
        local cpar
        for cpar in ${props//,/ }
        do 
            local nv=( ${cpar/=/ } )
            local pname=${nv[0]}
            local pvalue=${nv[1]}
            if [[ "${pname}" == *@* ]]
            then
                local idx=${pname/*@}
                pname=${pname/@*}
                if (( idx == node_num ))
                then
                    log "Setting property at specific node #${node_num}: [${pname} = ${pvalue}]"
                    set_property "${prop_file}" "${pname}" "${pvalue}" =
                else
                    log "Skipping property at specific node #${node_num}: [${pname} = ${pvalue}]"
                fi
            else
                log "Setting property: [${pname} = ${pvalue}]"
                set_property "${prop_file}" "${pname}" "${pvalue}" =
            fi
        done
    fi
}

write_test_status() {
    local name=${1}
    local status=${2}
    local time=${3}
    [[ -n "${time}" ]] && time="spent ${time} seconds"
    log "Test ${name} ${status} ${time}"
    [[ -d "${RESULTS_DIR}" ]] && echo "${name}, ${status}, ${time}" >> "${RESULTS_DIR}/status.txt"
}

get_latency_scores() {
    local json=${1}
    local metrics=${2}
    local nolatency=${3}
    metrics=( ${metrics//,/ } )
    local metric_name
    local metric
    local scale
    local names
    local values
    for metric_name in "${metrics[@]}"
    do
        metric_name=$(echo ${metric_name})
        [[ -z "$metric_name" ]] && continue
        names=(` $jq -r '.doc.metrics[] | select(.operation == ''"'$metric_name'"'' and .name == ''"response_times"'') | .percentile_names | .[]' "$json" `)
        values=(` $jq -r '.doc.metrics[] | select(.operation == ''"'$metric_name'"'' and .name == ''"response_times"'') | .percentile_values | .[]' "$json" `)
        scale=` $jq -r '.doc.metrics[] | select(.operation == ''"'$metric_name'"'' and .name == ''"response_times"'') | .scale' "$json" `
        [[ "$scale" == microseconds ]] && scale=us
        [[ "$scale" == milliseconds ]] && scale=ms
        local name
        local value
        local n=${#names[@]}
        echo "#NAMES ${names[@]}"
        for (( i = 0; i < n ; i++ ))
        do
            name=${names[$i]}
            name=$(echo ${name} | sed "s|\\.0$||")
            [[ "${name}" == 0 ]] && continue
            value=$(echo ${values[$i]})
            echo "Score on ${metric_name}_${name}th_percentile_latency: ${value} ${scale}"
        done
    done
}

get_tusla_scores() {
    local json=${1}
    local names=$( $jq -r '.metrics[] | select(.name == ''"conforming rate"'') | .operation' "${json}" | sed "s| |_|g;")
    local units=$( $jq -r '.metrics[] | select(.name == ''"conforming rate"'') | .units' "${json}" )
    local values=$( $jq -r '.metrics[] | select(.name == ''"conforming rate"'') | .value' "${json}" )
    names=( ${names[@]} )
    units=( ${units[@]} )
    values=( ${values[@]} )
    local n=${#names[@]}
    local name
    local value
    local unit
    for (( i = 0; i < n ; i++ ))
    do
        #echo "$i: ${names[i]} = ${values[i]} ${units[i]}"
        name=$(echo ${names[i]} | sed "s|\\.0$||; s|_(unbroken)||; s|(serv)|serv|; s|(resp)|resp|; ")
        value=$(echo ${values[i]})
        unit=$(echo ${units[i]})
        echo "Score on ConformingRate_${name}: ${value} ${unit}"
    done
    value=$( $jq -r '.metrics[] | select(.name == ''"high bound"'') | .value' "${json}")
    unit=$( $jq -r '.metrics[] | select(.name == ''"high bound"'') | .units' "${json}")
    echo "Score on HighBound: ${value} ${unit}"
    value=$( $jq -r '.metrics[] | select(.name == ''"max rate"'') | .value' "${json}")
    unit=$( $jq -r '.metrics[] | select(.name == ''"max rate"'') | .units' "${json}")
    echo "Score on MaxRate: ${value} ${unit}"
}

t() {
    log "[TEST] Test [${@}]"
    "${@}"
    log "[TEST] Test result: $?"
}

test_ok() {
    return 0
}

test_err() {
    return 1
}

test_okerr() {
    test_ok
    ( test_err )
}

test_errok() {
    test_err
    ( test_ok )
}

test_hostname() {
    log ${HOSTNAME}
}

if [[ "${BASH_SOURCE}" == "${0}" ]]
then
    process_args "${@}"
    "${ARGS[@]}"
fi
