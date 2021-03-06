#!/bin/sh -xe

echoerr() {
    echo "$@" 1>&2
}

# Verify the time passed in fits the YYYYMM format.
#
# verifyTime "YYYYMM"
verifyTime () {
    local timeString=$@

    len=$( expr length "${timeString}" )
    if [[ $len -ne 6 ]]; then
        echoerr "FATAL: Time string is not in the correct format.  Expected 'YYYYMM'."
        echoerr "FATAL: Got '$timeString'."
        exit 65
    fi

    local yr=$( expr substr "${timeString}" 1 4 )
    local mo=$( expr substr "${timeString}" 5 2 )
    if [[ $yr -le 0 ]]; then
        echoerr "FATAL: Not a valid year.  Year must be greater than 0.  Got '$yr'."
        exit 65
    fi
    # The "10#" is needed to keep sh from using ocal numbers
    if [[ "10#$mo" -lt 1 || "10#$mo" -gt 12 ]]; then
        echoerr "FATAL: Not a valid month.  Month must be in the range [1,12].  Got '%mo'."
        exit 65
    fi
}

usage() {
    echo "Usage: do_oisst_qc.sh [OPTIONS]"
}

help () {
    usage
    echo ""
    echo "Options:"
    echo "     -h"
    echo "          Display usage information."
    echo ""
    echo "     -o <out_file>"
    echo "          Write the output to file <out_file> instead of default file"
    echo "          location."
    echo ""
    echo "     -t <YYYYMM>"
    echo "          Create OISST file for month MM and year YYYY"
    echo "          Default: Current year/month"
    echo ""
    echo "     -i <file>"
    echo "          Use the files in <file> to generate a specific file.  Must use"
    echo "          the -o and -t options, otherwise the script may think the file"
    echo "          has already been generated."
    echo ""
}

# Set the umask for world readable
umask 022

# Check limits
#ulimit -S -s unlimited
#ulimit -H -s unlimited
ulimit -a

# Location of this script
BIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Default settings for year/month
# Need everything for the previous month up the the first of the current month
# That is, we need to process ${yearPrev}0101 - ${yearCur}${monCur}01.
yearCur=$( date '+%Y' )
monCur=$( date '+%m' )

# Read in command line options
while getopts :ho:t:i: OPT; do
    case "$OPT" in
        h)
            help
            exit 0
            ;;
        o)
            OUTFILE=${OPTARG}
            ;;
        t)
            verifyTime ${OPTARG}
            yearCur=$( expr substr "${OPTARG}" 1 4 )
            monCur=$( expr substr "${OPTARG}" 5 2 )
            ;;
        i)
            inLogFile=${OPTARG}
            ;;
        \?)
            echoerr "Unknown option:" $${OPTARG}
            usage >&2
            exit 1
            ;;
    esac
done

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

# Output file
sst_cm2=sstcm2_daily_${s_yymmdd}_${e_yymmdd}.nc
if [[ -z $OUTFILE ]]; then
    # Set the default OUTFILE if not set by option above
    OUTFILE=${OUT_DIR}/${sst_cm2}
fi

# Begin actual work, need to be in WORK_DIR
cd ${WORK_DIR}

# Check of existance of the output file.  If it exists, exit
if [[ -e ${OUTFILE}.OK ]]; then
    echoerr "File '${OUTFILE}' already exists.  Not processing."
else
    # Get a list of files, and verify that all days in the range are present
    # $( date -d "2016-$m-01 + 1month - 1day" '+%d' ) get number of days in month
    # inFiles is a list of files to process
    inFiles=''

    if [[ -z $inLogFile ]]; then
        # Normal processing new files
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
        f_base=${RAW_DIR}/${yearCur}/avhrr-only-v2.${yearCur}${monCur}01
        if [ -e ${f_base}.nc ]; then
            inFiles="${inFiles} ${f_base}.nc"
        elif [ -e ${f_base}_preliminary.nc ]; then
            inFiles="${inFiles} ${f_base}_preliminary.nc"
        else
            echoerr "ERROR: Unable to find raw data file file for ${yearCur}-${monCur}-01"
            exit 1
        fi
    else
        # Process files in $inLogFile
        inFiles=$( cat $inLogFile )
    fi

    # Combine the daily files into a single file
    # Keep a history of which input files were used in the $OUTFILE.log file
    if [[ -e ${OUTFILE}.log ]]; then
        rm -f ${OUTFILE}.log
    fi

    # Output file for this step:
    sst_mean="sst.day.mean${year}.v2.nc"

    for f in $inFiles; do
        ferret <<EOF
set memory/size=1000
use "${f}"
save/app/file="${sst_mean}" sst
exit
EOF

        echo ${f} >> ${OUTFILE}.log
        # Remove the ferret file
        rm -f ferret*.jnl*
    done

    # Regrid the data for use with CM2 models
    ferret <<EOF
set memory/size=1000
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
    cp ${sst_cm2} ${OUTFILE}
    touch ${OUTFILE}.OK
fi

# Copy file to remote site
if [[ ! -z ${XFER_TARGET} ]]; then
    for f in ${OUTFILE} ${OUTFILE}.OK ${OUTFILE}.log
    do
        $XFER_COMMAND ${f} ${XFER_TARGET}
    done
fi
