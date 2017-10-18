#!/bin/sh
#
# Finnish Meteorological Institute / Mikko Rauhala (2015-2017)
#
# SmartMet Data Ingestion Module for ECMWF Model
#

# Load Configuration 
if [ -s /smartmet/cnf/data/ecmwf.cnf ]; then
    . /smartmet/cnf/data/ecmwf.cnf
fi

if [ -s ecmwf.cnf ]; then
    . ecmwf.cnf
fi

# Setup defaults for the configuration

if [ -z "$AREA" ]; then
    AREA=world
fi

if [ -z "$PROJECTION" ]; then
    P_ARG=""
else
    P_ARG="-P $PROJECTION"
fi


while getopts  "a:b:dg:i:l:r:t:" flag
do
  case "$flag" in
        a) AREA=$OPTARG;;
        d) DRYRUN=1;;
  esac
done

STEP=12
# Model Reference Time
RT=`date -u +%s -d '-3 hours'`
RT="$(( $RT / ($STEP * 3600) * ($STEP * 3600) ))"
RT_HOUR=`date -u -d@$RT +%H`
RT_DATE_MMDD=`date -u -d@$RT +%m%d`
RT_DATE_MMDDHH=`date -u -d@$RT +%m%d%H`
RT_DATE_HH=`date -u -d@$RT +%Y%m%d%H`
RT_DATE_HHMM=`date -u -d@$RT +%Y%m%d%H%M`
RT_ISO=`date -u -d@$RT +%Y-%m-%dT%H:%M:%SZ`

if [ -d /smartmet ]; then
    BASE=/smartmet
else
    BASE=$HOME/smartmet
fi

IN=$BASE/data/incoming/ecmwf/ESD
OUT=$BASE/data/ecmwf/$AREA
CNF=$BASE/run/data/ecmwf/cnf
EDITOR=$BASE/editor/in
TMP=$BASE/tmp/data/ecmwf_${AREA}_${RT_DATE_HHMM}
LOGFILE=$BASE/logs/data/ecmwf_${AREA}_${RT_HOUR}.log

OUTNAME=${RT_DATE_HHMM}_ecmwf_$AREA

# Use log file if not run interactively
if [ $TERM = "dumb" ]; then
    exec &> $LOGFILE
fi

echo "Model Reference Time: $RT_ISO"
echo "Projection: $PROJECTION"
echo "Temporary directory: $TMP"
echo "Input directory: $IN"
echo "Output directory: $OUT"
echo "Output surface level file: ${OUTNAME}_surface.sqd"
echo "Output pressure level file: ${OUTNAME}_pressure.sqd"


if [ -z "$DRYRUN" ]; then
    mkdir -p $OUT/{surface,pressure}/querydata
    mkdir -p $EDITOR
    mkdir -p $TMP
fi

if [ -n "$DRYRUN" ]; then
    exit
fi

function log {
    echo "$(date -u +%H:%M:%S) $1"
}

# Check if data conversion is already done and complete
if [ -s $OUT/surface/querydata/${OUTNAME}_surface.sqd ] && [ -s  $OUT/pressure/querydata/${OUTNAME}_pressure.sqd ]; then
    IN_COUNT=$(ls -1tr $IN/ESD${RT_DATE_MMDDHH}*|wc -l)

    SFC_COUNT=$(qdinfo -t -q $OUT/surface/querydata/${OUTNAME}_surface.sqd|grep Timesteps|cut -d= -f2| tr -d ' ')
    if [ $IN_COUNT -eq $SFC_COUNT ]; then
	log "${OUTNAME}_surface.sqd is complete"
    else
	log "${OUTNAME}_surface.sqd is incomplete"
	FAIL=1
    fi

    PL_COUNT=$(qdinfo -t -q $OUT/pressure/querydata/${OUTNAME}_pressure.sqd | grep Timesteps | cut -d= -f2 | tr -d ' ')
    if [ $(expr $IN_COUNT - 1) -eq $PL_COUNT ]; then
	log "${OUTNAME}_pressure.sqd is complete"
    else
	log "${OUTNAME}_pressure.sqd is incomplete"
	FAIL=1
    fi

    if [ -n $FAIL ]; then
	log "Converted data already exists."
	exit
    fi
fi

# Check if data needed is already available, if not weait maximum of 50 minutes
while [ 1 ]; do
    ((count=count+1))
    IN_RUN=$(ls -1tr $IN/|tail -1 | cut -c4-9)
    if  [ "$RT_DATE_MMDDHH" = "$IN_RUN" ]; then
	log "Data $IN_RUN available."
	break
    else
	log "Data $RT_DATE_MMDDHH not available. Old data available: $IN_RUN"
    fi
    # break if max count
    if [ $count = 50 ]; then break; fi;
    sleep 60
done # while 1

#
# Convert grib files to qd files
#
log "Converting pressure grib files to qd files."
gribtoqd -d -t -L 100 -c $CNF/ecmwf.conf -p "240,ECMWF Pressure" $P_ARG \
    -o $TMP/${OUTNAME}_pressure.sqd \
    $IN/ESD${RT_DATE_MMDDHH}*

log "Converting surface grib files to qd files."
gribtoqd -d -t -L 1 -c $CNF/ecmwf.conf -p "240,ECMWF Surface" $P_ARG \
    -o $TMP/${OUTNAME}_surface.sqd \
    $IN/ESD${RT_DATE_MMDDHH}*

#
# Post process some parameters 
#
log "Post processing ${OUTNAME}_pressure.sqd"
cp -f  $TMP/${OUTNAME}_pressure.sqd $TMP/${OUTNAME}_pressure.sqd.tmp
log "Post processing ${OUTNAME}_surface.sqd"
qdscript -a 354 $CNF/ecmwf-surface.st < $TMP/${OUTNAME}_surface.sqd > $TMP/${OUTNAME}_surface.sqd.tmp

#
# Create querydata totalWind and WeatherAndCloudiness objects
#
log "Creating Wind and Weather objects: ${OUTNAME}_pressure.sqd"
qdversionchange -w 0 7 < $TMP/${OUTNAME}_pressure.sqd.tmp > $TMP/${OUTNAME}_pressure.sqd
log "Creating Wind and Weather objects: ${OUTNAME}_surface.sqd"
qdversionchange -a 7 < $TMP/${OUTNAME}_surface.sqd.tmp > $TMP/${OUTNAME}_surface.sqd

#
# Copy files to SmartMet Workstation and SmartMet Production directories

# Pressure level
if [ -s $TMP/${OUTNAME}_pressure.sqd ]; then
    log "Testing ${OUTNAME}_pressure.sqd"
    if qdstat $TMP/${OUTNAME}_pressure.sqd; then
	log  "Compressing ${OUTNAME}_pressure.sqd"
	lbzip2 -k $TMP/${OUTNAME}_pressure.sqd
	log "Moving ${OUTNAME}_pressure.sqd to $OUT/pressure/querydata/"
	mv -f $TMP/${OUTNAME}_pressure.sqd $OUT/pressure/querydata/
	log "Moving ${OUTNAME}_pressure.sqd.bz2 to $EDITOR/"
	mv -f $TMP/${OUTNAME}_pressure.sqd.bz2 $EDITOR/
    else
        log "File $TMP/${OUTNAME}_pressure.sqd is not valid qd file."
    fi
fi

# Surface
if [ -s $TMP/${OUTNAME}_surface.sqd ]; then
    log "Testing ${OUTNAME}_surface.sqd"
    if qdstat $TMP/${OUTNAME}_surface.sqd; then
        log "Compressing ${OUTNAME}_surface.sqd"
	lbzip2 -k $TMP/${OUTNAME}_surface.sqd
        log "Moving ${OUTNAME}_surface.sqd to $OUT/surface/querydata/"
	mv -f $TMP/${OUTNAME}_surface.sqd $OUT/surface/querydata/
	log "Moving ${OUTNAME}_surface.sqd.bz2 to $EDITOR"
	mv -f $TMP/${OUTNAME}_surface.sqd.bz2 $EDITOR/
    else
        log "File $TMP/${OUTNAME}_surface.sqd is not valid qd file."
    fi
fi

log "Cleaning temporary directory $TMP"
rm -f $TMP/*_ecmwf_*
rmdir $TMP
