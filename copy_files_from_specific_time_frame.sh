#!/usr/bin/env bash
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root"
  exit 1
fi
#pid=$$
HISTORY_FILE=$(dirname "${0}")/.$(basename "${0}" .sh)_history
formats="YYYY-MM-DD hh:mm or YYYYMMDD hh:mm"
[ ! -f "${HISTORY_FILE}" ] && touch "${HISTORY_FILE}"
history -r "${HISTORY_FILE}"
set -o vi
sed -i '/^$/d' "${HISTORY_FILE}"
rename=0
function array_contains() { # array value
  [[ -n "$1" && -n "$2" ]] || {
    echo "usage: array_contains <array> <value>"
    echo "Returns 0 if array contains value, 1 otherwise"
    return 1
  }

  # shellcheck disable=SC2086
  eval 'local values=("${'$1'[@]}")'

  local element
  # shellcheck disable=SC2154
  for element in "${values[@]}"; do
    [[ "$element" == "$2" ]] && return 0
  done
  return 1
}

function get_help() {
  echo
  echo -e "${0} [args]

[-f | --from]                   Date To Find From, Excepted Date Format: ${formats}
[-t | --to]                     Date To Find To, Excepted Date Format: ${formats}
[-s | --source]                 Source Directory
[-d | --destination]            Destination Directory


Optional args:

[-c | --clear]                  Clear Script History
[-a | --auto]                   Assume all files are in the same directory
[-S | --sum]                    Get summary of the collected files and exit 
[-l | --filter-list <txt file>] List of mongo id's that would be used as filter [ must be specified with --ignore or --exclusive switch but can't be specified with --filter ]
[-F | --filter <arg>]           Mongo id that would be used as filter [ must  be specified with --ignore or --exclusive switch but can't be specified with --filter-list ]
[-x | --exclusive]              Leave only files/directories that match the filter
[-i | --ignore]                 Ignore files/directories that match the filter
[-r | --rename <csv file>]      Rename folders during copy
[-p | --pattern]                Specify pattern to search for, exp: *.ts"

  echo
  exit 0
}
args=("$@")
i=0
if (array_contains args "-l" || array_contains args "--filter-list") && (array_contains args "-F" || array_contains args "--filter"); then
  echo "filter-list can't be specify with filter, please pick one and try again"
  exit 0
fi

if ( (array_contains args "-l" || array_contains args "--filter-list") || (array_contains args "-F" || array_contains args "--filter")) && (! array_contains args "-i" && ! array_contains args "--ignore" && ! array_contains args "-x" && ! array_contains args "--exclusive"); then
  echo "filter-list or filter must be specify with ignore or exclusive switch"
  exit 0
fi

for item in "${args[@]}"; do
  case $item in
  "-c" | "--clear")
    truncate -s 0 "${HISTORY_FILE}"
    echo "${0} history was cleared"
    exit 0
    ;;

  "-a" | "--auto")
    res="Y"
    ;;

  "-S" | "--sum")
    res="S"
    ;;

  "-l" | "--filter-list")
    [ "${args[((i + 1))]:0:1}" != '-' ] && filter=$(cat "${args[((i + 1))]}")
    ;;

  "-F" | "--filter")

    [ "${args[((i + 1))]:0:1}" != '-' ] && filter="${args[((i + 1))]}"
    ;;

  "-i" | "--ignore")
    mode=0
    ;;

  "-x" | "--exclusive")
    mode=1

    ;;

  "-r" | "--rename")
    rename=1
    file=$(basename "${args[((i + 1))]}")
    if [ "${args[((i + 1))]:0:1}" != '-' ] && [ -f "${args[((i + 1))]}" ]; then
      if [ "${file##*.}" == "csv" ]; then
        mongo_list="${args[((i + 1))]}"
      else
        echo "The file must be csv"
        exit 1
      fi
    else
      echo "csv file dose not exist or you didn't specify the path to the csv file"
      exit 1
    fi

    ;;

  "-p" | "--pattern")
    [ "${args[((i + 1))]:0:1}" != '-' ] && pattern="${args[((i + 1))]}"
    ;;

  "-f" | "--from")
    if [ "${args[((i + 1))]:0:1}" != '-' ]; then
      tmp_from_Date="${args[((i + 1))]}"
      if [[ ("${args[((i + 2))]:0:1}" != '-') && ("${args[((i + 2))]:0:1}" == ?(-)+([0-9])) ]]; then
        if ! date "+%H:%M" -d "${args[((i + 2))]}" >/dev/null 2>&1; then
          #        if [ $? -eq 0 ]; then
          tmp_from_Time="$(date \"+%H:%M\" -d \""${args[((i + 2))]}"\")"
        else
          tmp_from_Time=" "
        fi
      else
        tmp_from_Time=" "
      fi
      from="${tmp_from_Date} ${tmp_from_Time}"
    fi
    ;;

  "-t" | "--to")
    if [ "${args[((i + 1))]:0:1}" != '-' ]; then
      tmp_to_Date="${args[((i + 1))]}"
      if [[ ("${args[((i + 2))]:0:1}" != '-') && ("${args[((i + 2))]:0:1}" == ?(-)+([0-9])) ]]; then
        if ! date "+%H:%M" -d "${args[((i + 2))]}" >/dev/null 2>&1; then
          tmp_to_Time="$(date \"+%H:%M\" -d \""${args[((i + 2))]}"\")"
        else
          tmp_to_Time=" "
        fi
      else
        tmp_to_Time=" "
      fi
      to="${tmp_to_Date} ${tmp_to_Time}"
    fi
    ;;

  "-s" | "--source")
    [ "${args[((i + 1))]:0:1}" != '-' ] && source=${args[((i + 1))]}
    ;;

  "-d" | "--destination")
    [ "${args[((i + 1))]:0:1}" != '-' ] && destination=${args[((i + 1))]}
    ;;

  "-h" | "--help")
    get_help
    ;;
  esac
  ((i++))

done

function test_if_ssh_path() {
  local arg=$1
  local stat=1
  ip=$(echo "${arg}" | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}')
  if [[ "${ip}" =~ [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3} ]]; then
    IFS='.' read -ra ip <<<"${ip}"
    [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
    stat=$?
  fi
  return ${stat}
}

function getHostName() {
  hostname
}

function path_exist() {
  local path="${1}"
  [ -z "${path}" ] && return 1
  if test_if_ssh_path "${path}"; then
    IFS=':' read -ra a <<<"${path}"
    [ -z "${a[1]}" ] && return 1
    # shellcheck disable=SC2029
    if ssh "${a[0]}" "[ -d ${a[1]} ]"; then
      return 0
    else
      return 1
    fi
  else
    if [ -d "${path}" ]; then
      return 0
    else
      return 1
    fi
  fi
}

function sshHelper() {
  local sshPath="${1}"
  local func="${2}"
  shift 2
  args=("$@")
  parms=()
  for item in "${args[@]}"; do
    parms+=("${item}")
  done
  IFS=':' read -ra a <<<"${sshPath}"
  # shellcheck disable=SC2029
  ssh "${a[0]}" "$(declare -f "$func"); $func ${parms[*]};"
}

function processDone() {
  printf "\n%s\n" "Done"
}

function getRaw() {
  var=("$@")
  data=$(
    IFS=$'\n'
    echo "${var[*]}"
  )
  while IFS= read -r arg; do
    line="${arg##*:}"
    total=$((total + $(du -b "$line" | awk '{print $1}')))
    #       let "total+=$(du -B 1K "$line" | awk '{print $1}')"
  done <<<"${data}"
  echo $total
}

function prettyFormat() {
  local raw="$1"
  unit=$(printf %.3f "$(echo "$raw / 1024" | bc -l)")
  if [ "$(echo "${unit} < 1" | bc -l)" -eq 0 ]; then
    if [ "$(echo "${unit} <= 1024" | bc -l)" -eq 1 ]; then
      totalSize="${unit}KB"
    elif [ "$(echo "${unit} < 1048576" | bc -l)" -eq 1 ]; then
      totalSize="$(printf %.3f "$(echo "$unit / 1024" | bc -l)")MB"
    else
      totalSize="$(printf %.3f "$(echo "$unit / 1024 / 1024" | bc -l)")GB"
    fi
  else
    totalSize="${raw} Bytes"
  fi
  echo "${totalSize}"

}

function validateDateHelper() {
  local format=$1
  local data=$2
  [ -z "$data" ] && return 1
  date "+${format}" -d "${data}" >/dev/null 2>&1
  return $?
}

function validateDate() {
  local data=$1
  local format=$2
  local sender=$3
  while (! validateDateHelper "${format}" "${data}"); do
    read -r -e -p "${sender} DateTime (${formats}): " data
  done
  date "+${format}" -d "${data}"
}

function getSource() {
  read -r -e -p "Source Dir: " source
}

function getDestination() {
  read -r -e -p "Destination Dir: " destination
}

function rename() {
  #  local HOSTNAME="${1}"
  dirList="/tmp/${HOSTNAME}_${Date}_Dirs_List.txt"
  find "${destination}" -type d | uniq >"${dirList}"
  while read -r LINE; do
    while IFS=',' read -r id name; do
      if [[ "$LINE" =~ ${id} ]]; then
        cd "${LINE%${id}*}" || exit
        # cd "$(echo "${LINE}" | sed "s!${id}.*!!")" || exit
        if [ -d "${id}" ]; then
          mv "${id}" "${name}"
          printf "\n%s\n" "${LINE} -> ${name}"
        fi
        break
      fi
    done <"${mongo_list}"
  done <"${dirList}"
}

function validateDiff() {
  local from="${1}"
  local to="${2}"
  while [[ $(date -d "$from" +%s) -gt $(date -d "$to" +%s) ]]; do
    from="" to=""
    echo
    echo "FromDate is ahead of the ToDate try again!"
    echo
    from=$(validateDate "${from}" "%Y%m%d %H:%M" "From")
    to=$(validateDate "${to}" "%Y%m%d %H:%M" "To")
  done
}

function extractDataTime() {
  local DateTime="${1}"
  local sender="${2}"
  IFS=' ' read -r -a array <<<"${DateTime}"
  if [[ $sender == "From" ]]; then
    fromDate=$(date -d "${array[0]}" +%Y-%m-%d)
    fromTime=${array[1]/":"/""}
  else
    toDate=$(date -d "${array[0]}" +%Y-%m-%d)
    toTime=${array[1]/":"/""}
  fi

}

function getFileList() {
  local src="${1}"
  local since="${2}"
  local upTo="${3}"
  local prefix="${4}"
  local srcTerm="${5}"
  find "${src}" -newermt "${since}" -not -newermt "${upTo}" -type f "${srcTerm}" -printf "${prefix}%p\n"
}

function getFullFileList() {
  var=("$@")
  fileList=$(
    IFS=$'\n'
    echo "${var[*]}"
  )
  while IFS= read -r line; do
    file="${line##*:}"
    ls -ltr "${file}"
  done <<<"${fileList}"
}

function isFileEmpty() {
  local file="${1}"
  local HOSTNAME="${2}"
  if [ ! -s "${file}" ]; then
    echo
    echo "Can't find files that match this search try again with different parameters"
    echo
    rm "${tmpList}" "${Helper}" "/tmp/${HOSTNAME}" >/dev/null 2>&1
    exit 0
  fi
}

function FilterExist() {
  local tmpPath="${1}"
  local fullPath="${2}"
  local parm="${3}"
  local keep="${4}"
  if [ -n "${param}" ]; then
    [ -f "${tmpPath}" ] && truncate -s 0 "${tmpPath}"
    for term in ${parm}; do
      if [ "${keep}" -eq 0 ]; then
        sed -i "/\b${term}\b/d" "${fullPath}"
      else
        sed -n "/\b${term}\b/p" "${fullPath}" >>"${tmpPath}"
      fi
    done
    [ -f "${tmpPath}" ] && mv "${tmpPath}" "${fullPath}" -f
  fi
}

function main() {
  from=$(validateDate "${from}" "%Y%m%d %H:%M" "From")
  to=$(validateDate "${to}" "%Y%m%d %H:%M" "To")
  validateDiff "$from" "$to"
  history -s "${from}"
  history -s "${to}"
  history -w "$HISTORY_FILE"

  while (! path_exist "${source}"); do
    [ -z "${source}" ] && source="Path"
    echo
    echo "$source dose not exist, Please try again"
    echo
    getSource
  done

  if [ "$res" == "S" ]; then
    destination="/tmp"
  else
    while (! path_exist "${destination}"); do
      if ! mkdir -p ${destination} >/dev/null 2>&1; then
        getDestination
      fi
    done
  fi
  if test_if_ssh_path ${source}; then
    declare -x TYPE="SSH"
    IFS=':' read -ra a <<<${source}
    declare SOURCE_ARR="${a[0]}"
    declare HOSTNAME
    HOSTNAME=$(sshHelper "${SOURCE_ARR}" "getHostName")
  else
    declare -x TYPE="LOCAL"
    declare HOSTNAME
    HOSTNAME=$(getHostName)
  fi

  history -s $source
  history -s $destination
  history -w "${HISTORY_FILE}"

  [ "${destination: -1}" == "/" ] && destination="${destination::-1}"
  base_destination=${destination}
  extractDataTime "${from}" "From"
  extractDataTime "${to}" "To"

  if [ "${fromDate}" == "${toDate}" ]; then
    Date=${fromDate}
    Time=${fromTime}-${toTime}
    destination="${destination}/${HOSTNAME}/${Date}/${Time}"
  else
    Date="${fromDate}T${fromTime}__${toDate}T${toTime}"
    destination="${destination}/${HOSTNAME}/${Date}"
  fi
  if (! path_exist "${destination}"); then
    mkdir -p "${destination}"
  fi
  [ ! "${source: -1}" == "/" ] && source="${source}/"

  tmpList="/tmp/${Date}-${Time}.txt"
  Helper="/tmp/${Date}-${Time}.tmp"
  if [[ "${TYPE}" == "SSH" ]]; then
    src=${source##*:}
    ssh=${source%:*}
    parms=("${src}" "\"${from}\"" "\"${to}\"" "${ssh}:" "${pattern}")
    sshHelper "${ssh}" "getFileList" "${parms[@]}" >"${Helper}"
    isFileEmpty "${Helper}" "${HOSTNAME}"
    unset parms
    sshHelper "${ssh}" "getFullFileList" "$(<"${Helper}")" >"${destination}/${HOSTNAME}_Full_List.tmp"
  else
    getFileList "${source}" "${from}" "${to}" '' "${pattern}" >"${Helper}"
    isFileEmpty "${Helper}" "${HOSTNAME}"
    getFullFileList "$(<"${Helper}")" >"${destination}/${HOSTNAME}_Full_List.tmp"
  fi

  sort -Vk9 "${destination}/${HOSTNAME}_Full_List.tmp" >"${destination}/${HOSTNAME}_Full_List.txt"
  rm -f "${destination}/${HOSTNAME}_Full_List.tmp"
  FilterExist "${destination}/${HOSTNAME}_List.txt" "${destination}/${HOSTNAME}_Full_List.txt" "${filter}" ${mode}
  sort -V "${Helper}" >"${destination}/${HOSTNAME}_Filtered_List.txt"
  grep -oP "^$source\K.*" "${destination}/${HOSTNAME}_Filtered_List.txt" >"${tmpList}"

  if [ "${res}" == "S" ]; then
    if [[ "${TYPE}" == "SSH" ]]; then
      parm=("${Helper}")
      echo "Total Size: $(prettyFormat "$(sshHelper "${SOURCE_ARR}" "getRaw" "$(<"${Helper}")")")"
    else
      echo "Total Size: $(prettyFormat "$(getRaw "$(<"${Helper}")")")"
    fi
    echo "Number of files: $(wc <"${destination}/${HOSTNAME}_Filtered_List.txt" -l)"
    #rm -rf "${tmpList}" "${Helper}" >/dev/null 2>&1
  else
    while true; do
      if [[ "${TYPE}" == "SSH" ]]; then
        list="${destination}/${HOSTNAME}_Filtered_List.txt"
        sourceSize=$(sshHelper "${SOURCE_ARR}" "getRaw" "$(<"${list}")")
      else
        FullList=${destination}/${HOSTNAME}_Filtered_List.txt
        sourceSize=$(getRaw "$(<"${FullList}")")
      fi
      destinationFreeSize=$(df "${destination}" | sed 1d | tr -s " " | cut -d' ' -f4)
      if [ "${sourceSize}" -gt "${destinationFreeSize}" ]; then
        diff=$(("${sourceSize}" - "${destinationFreeSize}"))
        neededSpace=$(prettyFormat $diff)
        echo "There is not enough disk space on ${destination}, needs: ${neededSpace}"
        break
      fi

      if [ "${res}" != Y ]; then
        read -r -e -p "Are all the files in the same source dir? (Y=Yes, N=No): " ans
      else
        ans="Y"
      fi

      case $ans in
      Y | y)
        echo -e "\nThe backup process hes started in the background\nYou can watch the progress by using:\n\t tail -f ${destination}/${HOSTNAME}_Progress_log.log\n\n You will get a massage ones it's done"
        (rsync -aRp --progress --files-from="${tmpList}" ${source} "${destination}" >"${destination}/${HOSTNAME}_Progress_log.log" 2>&1 && processDone && rm "${tmpList}" "${Helper}" >/dev/null 2>&1 && ([ $rename -eq 1 ] && rename && rm "${dirList}") && chown -R "$(logname)":"$(logname)" ${base_destination} >/dev/null 2>&1) &
        disown
        break
        ;;

      N | n)
        echo -e "\nThe backup process hes started in the background\nYou can watch the progress by using:\n\t tail -f ${destination}/${HOSTNAME}_Progress_log.log\n\n You will get a massage ones it's done"
        cd ${source} || exit
        (rsync -aRp --progress "$(cat "${tmpList}")" "${destination}" >"${destination}/${HOSTNAME}_Progress_log.log" 2>&1 && processDone && rm "${tmpList}" "${Helper}" >/dev/null 2>&1 && ([ ${rename} -eq 1 ] && rename && rm "${dirList}") && chown -R "$(logname)":"$(logname)" ${base_destination} >/dev/null 2>&1) &
        disown
        break
        ;;

      *)
        echo "You picked a non exiting option please try again"
        ;;
      esac
    done
  fi
}

main
