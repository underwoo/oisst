#!/bin/sh -xe

# Set the umask for world readable
umask 022

# Setup the environment, and Ferret
# Ferret module is only needed for me (Seth.Underwood)
. /usr/local/Modules/3.1.6/init/sh
module use -a /home/sdu/privatemodules
module load netcdf/4.2
module load nco
module load ferret

# Get the current year.  This is the year to process.
year=$( date '+%Y' )

# Useful PATHS
BASE_DIR=/local2/home/oisst
DATA_DIR=/local/home/oisst_qc/data
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
for f in $( ls -1 ${RAW_DIR}/*.${year}????.nc ${RAW_DIR}/*.${year}????_preliminary.nc ); do
    file=$(basename $f)
    months="${months} ${file:18:2}"
done
# Get a unique value for each month
months=$( echo ${months} | sed -e 's/ /\n/g' | sort -u )

# Combine the daily files into a single file
# Output file for this step:
sst_mean="sst.day.mean${year}.v2.nc"

for m in  $months; do
    # Get the number of days for this month
    days=
    for f in $( ls -1 ${RAW_DIR}/*.${year}${m}??.nc ${RAW_DIR}/*.${year}${m}??_preliminary.nc ); do
	file=$(basename $f)
	days="${days} ${file:20:2}"
    done
    # Get a unique value for each day
    days=$( echo ${days} | sed -e 's/ /\n/g' | sort -u )

    # Process each file, and combine into a single yearly file.
    for d in ${days}; do
	# Need to know the first date processed.
	if [ -z ${firstDate} ]; then
	    firstDate="${m}/${d}/${year}"
	fi

	# Do we need to use the preliminary data?
	if [ -e ${RAW_DIR}/avhrr-only-v2.${year}${m}${d}.nc ]; then
	    infile=${RAW_DIR}/avhrr-only-v2.${year}${m}${d}.nc
	elif [ -e ${RAW_DIR}/avhrr-only-v2.${year}${m}${d}_preliminary.nc ]; then
	    infile=${RAW_DIR}/avhrr-only-v2.${year}${m}${d}_preliminary.nc
	else
	    echo "ERROR: Unable to find file avhrr-only-v2.${year}${m}${d}\*.nc"
	    exit 1
	fi
	ferret <<EOF
use "${infile}"
save/app/file="${sst_mean}" sst
exit
EOF
	# Remove the ferret file
	rm -f ferret*.jnl*

	# Also need to know the last date processed
	lastDate="${m}/${d}/${year}"
    done
done

# Regrid the data for use with CM2 models
# Convert the start/end Dates from above to d-mmm-yyyy and yymmdd
sDate=$( date -d $firstDate '+%-d-%b-%Y' )
eDate=$( date -d $lastDate '+%-d-%b-%Y' )
s_yymmdd=$( date -d $firstDate '+%y%m%d' )
e_yymmdd=$( date -d $lastDate '+%y%m%d' )

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
