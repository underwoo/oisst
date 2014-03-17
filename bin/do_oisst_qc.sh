#!/bin/sh -xe

echoerr() {
    echo "$@" 1>&2
}

# Set the umask for world readable
umask 022

# Location of this script
BIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source the env.sh file for the current environment, or exit if it doesn't exit.
if [[ ! -e ${BIN_DIR}/env.sh ]]; then
    echoerr "ERROR: Environment script '${BIN_DIR}/env.sh' doesn't exits."
    exit 1
fi
. ${BIN_DIR}/env.sh

# Useful PATHS
DATA_DIR=$( dirname ${BIN_DIR} )/data
GRID_SPEC=${DATA_DIR}/grid_spec.nc

# Check for the existance of the grid_spec file
if [[ ! -e ${GRID_SPEC} ]]; then
    echoerr "Cannot find the grid specification file ${GRID_SPEC}."
    exit 1
fi

# Check for the existance of the work and raw data directories
if [[ -z ${RAW_DIR} ]]; then
    echoerr "The variable RAW_DATA needs to be set in the configuration file ${BIN_DIR}/env.sh."
    exit 1
elif [[ ! -e ${RAW_DIR} ]]; then
    echoerr "Raw data not available"
    exit 1
fi

# Create the output directory
if [[ -z ${OUT_DIR} ]]; then
    echoerr "The variable OUT_DIR needs to be set in the configuration file ${BIN_DIR}/env.sh."
    exit 1
elif [ ! -e ${OUT_DIR} ]; then
    mkdir -p ${OUT_DIR}
fi

# Verify the WORK_DIR is set
if [[ -z ${WORK_DIR} ]]; then
    echoerr "The variable WORK_DIR needs to be set in the configuration file ${BIN_DIR}/env.sh."
    exit 1
fi

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

# Need everything for the previous month up the the first of the current month
# That is, we need to process ${yearPrev}0101 - ${yearCur}${monCur}01.
yearCur=$( date '+%Y' )
monCur=$( date '+%m' )
# Get the year and month for current date - 1month
yearPrev=$( date -d "${yearCur}-${monCur}-01 - 1month" '+%Y' )
monPrev=$( date -d "${yearCur}-${monCur}-01 - 1month" '+%m' )

# Convert the start/end Dates  to d-mmm-yyyy and yymmdd
firstDate="${yearPrev}-01-01"
lastDate="${yearCur}-${monCur}-01"
sDate=$( date -d $firstDate '+%-d-%b-%Y' )
eDate=$( date -d $lastDate '+%-d-%b-%Y' )
s_yymmdd=$( date -d $firstDate '+%y%m%d' )
e_yymmdd=$( date -d $lastDate '+%y%m%d' )

# Get a list of files, and verify that all days in the range are present
# $( date -d "2016-$m-01 + 1month - 1day" '+%d' ) get number of days in month
# inFiles is a list of files to process
inFiles=''

for m in $( seq -f '%02g' 1 $monPrev ); do
    daysInMonth=$( date -d "${yearPrev}-${m}-01 + 1month - 1day" '+%d' )

    for d in $( seq -f '%02g' 1 $daysInMonth ); do
	f_base=${RAW_DIR}/${yearPrev}/avhrr-only-v2.${yearPrev}${m}${d}
	# Do we need to use the preliminary data?
	if [ -e ${f_base}.nc ]; then
	    inFiles="${inFiles} ${f_base}.nc"
	elif [ -e ${f_base}_preliminary.nc ]; then
	    inFiles="${inFiles} ${f_base}_preliminary.nc"
	else
	    echoerr "ERROR: Unable to find raw data file file for ${yearPrev}-${m}-${d}"
	    exit 1
	fi
    done
done

# Check for the existance of ${yearCur}-${monCur}-01
f_base=${RAW_DIR}/${yearCur}/avhrr-only-v2.${yearPrev}${monCur}01
if [ -e ${f_base}.nc ]; then
    inFiles="${inFiles} ${f_base}.nc"
elif [ -e ${f_base}_preliminary.nc ]; then
    inFiles="${inFiles} ${f_base}_preliminary.nc"
else
    echoerr "ERROR: Unable to find raw data file file for ${yearPrev}-${m}-${d}"
    exit 1
fi

# Combine the daily files into a single file
# Output file for this step:
sst_mean="sst.day.mean${year}.v2.nc"

for f in $inFiles; do
    ferret <<EOF
use "${infile}"
save/app/file="${sst_mean}" sst
exit
EOF

    # Remove the ferret file
    rm -f ferret*.jnl*
done

# Regrid the data for use with CM2 models
# Output file for this step:
sst_cm2=sstcm2_daily_${s_yymmdd}_${e_yymmdd}.nc

ferret <<EOF
set memory/size=1280
use "${DATA_DIR}/grid_spec.nc"
use "${sst_mean}"
let temp = sst[gx=GEOLON_T[d=1],gy=GEOLAT_T[d=1],t=${sDate}:${eDate}]
save/clobber/file=tmp1.nc temp
exit
EOF
rm -f ferret*.jnl*

# Rename variables
ncrename -v TEMP,temp tmp1.nc
ncrename -v TIME,t tmp1.nc
ncrename -v GRIDLON_T,gridlon_t tmp1.nc
ncrename -v GRIDLAT_T,gridlat_t tmp1.nc
ncrename -d TIME,t tmp1.nc
ncrename -d GRIDLON_T,gridlon_t tmp1.nc
ncrename -d GRIDLAT_T,gridlat_t tmp1.nc

# average away the z-axis in file 2 and removing the ZLEV variable
ncwa -O -h -a ZLEV tmp1.nc tmp2.nc
ncrcat -O -h -x -v ZLEV tmp2.nc ${sst_cm2}

# Save file
cp ${sst_cm2} ${OUT_DIR}/${sst_cm2}
