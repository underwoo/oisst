#!/bin/sh -xe

# Setup the environment, and Ferret
# Modules are only needed for me (Seth.Underwood)
. /usr/local/Modules/3.1.6/init/sh
module use -a /home/sdu/privatemodules
module load ferret

# Get the current year.  This is the year to process.
year=$( date '+%Y' )

# Useful PATHS
BASE_DIR=/local2/home/oisst
RAW_DIR=${BASE_DIR}/raw/${year}
WORK_DIR=${BASE_DIR}/work
OUT_DIR=${BASE_DIR}/NetCDF

# Remove old work directory, and recreate.
if [ -e ${WORK_DIR} ]; then
    rm -rf ${WORK_DIR}
fi
mkdir -p ${WORK_DIR}

# Verify the output directory exists
if [ ! -e ${OUT_DIR} ]; then
    mkdir -p ${OUT_DIR}
fi

cd ${WORK_DIR}

# Get a list of months to process
months=
for f in $( ls -1 ${RAW_DIR}/*.${year}????.nc ); do
    file=$(basename $f)
    months="${months} ${file:18:2}"
done
# Get a unique value for each month
months=$( echo ${months} | sed -e 's/ /\n/g' | sort -u )

for m in  $months; do
    # Get the number of days for this month
    days=
    for f in $( ls -1 ${RAW_DIR}/*.${year}${m}??.nc ); do
	file=$(basename $f)
	days="${days} ${file:20:2}"
    done
    # Get a unique value for each day
    days=$( echo ${days} | sed -e 's/ /\n/g' | sort -u )

    # Process each file, and combine into a single yearly file.
    for d in ${days}; do
	ferret <<EOF
use "${RAW_DIR}/avhrr-only-v2.${year}${m}${d}.nc"
save/app/file="sst.day.mean${year}.v2.nc" sst
exit
EOF

	# Remove the ferret file
	rm -f ferret*.jnl
    done
done
