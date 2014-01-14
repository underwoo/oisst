#!/bin/sh

# Change umask to allow all read access
umask 022

# Get the current year
year=$( date '+%Y' )

# Setup the working directories
DATA_DIR=/local2/home/oisst/raw/${year}

if [ ! -e ${DATA_DIR} ]; then
    mkdir -p ${DATA_DIR}
fi
cd ${DATA_DIR}

# Transfer
dateString=$( date )
start_time=$( date -d "$dateString" '+%s' )

echo "Starting ARGO transfer"
echo $dateString

wget --read-timeout=60 --tries=10 --continue -r -N -nd ftp://eclipse.ncdc.noaa.gov/pub/OI-daily-v2/NetCDF-uncompress/${year}/AVHRR/

end_time=$( date '+%s' )
((run_time=end_time-start_time))
echo "Transfer finished successfully in ${run_time} seconds."
echo $( date )
