#!/bin/sh

# Change umask to allow all read access
umask 022

# Location of this script
BIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source the env.sh file for the current environment, or exit if it doesn't exit.
if [[ ! -e ${BIN_DIR}/env.sh ]]; then
    echoerr "ERROR: Environment script '${BIN_DIR}/env.sh' doesn't exits."
    exit 1
fi
. ${BIN_DIR}/env.sh

# Get the current year
year=$( date '+%Y' )

if [ ! -e ${RAW_DIR}/${year} ]; then
    mkdir -p ${RAW_DIR}/${year}
fi
cd ${RAW_DIR}/${year}

# Transfer
dateString=$( date )
start_time=$( date -d "$dateString" '+%s' )

echo "Starting ARGO transfer"
echo $dateString

wget --read-timeout=60 --tries=10 --continue -r -N -nd ftp://eclipse.ncdc.noaa.gov/pub/OI-daily-v2/NetCDF-uncompress/${year}/AVHRR/

# May need to get the previous year
yearPrev=$( date -d '-1month' '+%Y' )
if [[ $year -ne $yearPrev ]]; then
    if [ ! -e ${RAW_DIR}/${yearPrev} ]; then
	mkdir -p ${RAW_DIR}/${yearPrev}
    fi
    cd ${RAW_DIR}/${yearPrev}

    wget --read-timeout=60 --tries=10 --continue -r -N -nd ftp://eclipse.ncdc.noaa.gov/pub/OI-daily-v2/NetCDF-uncompress/${yearPrev}/AVHRR/
fi

end_time=$( date '+%s' )
((run_time=end_time-start_time))
echo "Transfer finished successfully in ${run_time} seconds."
echo $( date )
