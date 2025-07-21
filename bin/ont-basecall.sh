#! /usr/bin/env bash
# re-basecall and demux with dorado in a tmux

# IMPORTANT
# ln -s both bin/dorado and lib/lib to /usr/local/bin and /usr/local/lib

usage="$(basename "$0") [-m model] [-p pod5] [-k kit] [-r] [-b] [-t] [-f] [-h]

Basecall and optionally demultiplex pod5 files using dorado. 
Results folder (named basecall-model) will be in the path of the selected pod5 folder.
Options:
    -m  (required) dorado model, either fast, hac, or sup
    -p  (required) path to ONT pod5 folder
    -k  (optional) barcoding kit, if used demultiplexing will be performed (SQK-NBD114-96, SQK-RBK114-96 ...)
    -r  (optional flag) find pod5 files recursively
    -b  (optional flag) save reads in bam files, (fastq.gz by default)
    -t  (optional flag) trim adapters
    -q  (optional) filter by minimum read q-score (default 10)
    -f  (optional flag) save reads in barcodeXX folders (mimic MinKNOW output)"

recurs=false
bam=false
folders=false
trimmer=false
qfilter=10

unset -v model
unset -v podpath
unset -v kit

while getopts :hrbftm:p:k:q: flag
do
   case "${flag}" in
      h) echo "$usage"; exit;;
      m) model=${OPTARG};;
      p) podpath=${OPTARG};;
      k) kit=${OPTARG};;
      r) recurs=true;;
      b) bam=true;;
      t) trimmer=true;;
      q) qfilter=${OPTARG};;
      f) folders=true;;
      :) printf "missing argument for -%s\n" "$OPTARG" >&2; echo "$usage" >&2; exit 1;;
     \?) printf "illegal option: -%s\n" "$OPTARG" >&2; echo "$usage" >&2; exit 1;;
   esac
done

if [ -z "$model" ] || [ -z "$podpath" ]; then
        echo 'Missing -p or -m' >&2
        exit 1
fi

# check for dorado
if ! command -v dorado > /dev/null 2>&1; then 
    printf "dorado executable not found\n"
    exit 1
else
    dorado_version=$(dorado --version 2>&1) # version is sent to stderr
fi
# check for output directory, make it same level as the main run folder, e.g. parent of pod5 dir
run_directory=$(dirname $podpath)
model_prefix=$(basename $model | cut -d_ -f1,2)
output_directory=$(dirname $podpath)/basecall-$model_prefix

[ -d $output_directory ] && \
echo -e "Basecalled folder exists, will be deleted ...\n=============================="
# read -p "Continue (y/n)?" choice
# case "$choice" in 
#   y|Y ) rm -rf $output_directory;;
#   n|N ) echo "Exiting.." && exit 1;;
#   * ) echo "Creating output directory: $(realpath $output_directory)";;
# esac

npod5files=$(find $podpath -name "*.pod5" | wc -l | tr -d ' ')

mkdir -p "$output_directory"

if [[ $bam == 'true' ]]; then
    outfile="reads-$model_prefix.bam"
    emit=""
else
    outfile="reads-$model_prefix.fastq"
    emit="--emit-fastq"
fi

if [[ $recurs == 'true' ]]; then
    rec="-r"
else
    rec=""
fi

if [[ $trimmer == 'true' ]]; then
    trim="--trim adapters"
else
    trim=""
fi

if [ -z "$kit" ]; then
    demux=false
else
    demux=true
fi

SECONDS=0
echo "------------------------"
if [[ $demux == 'false' ]]; then
    echo -e "[$(date +"%Y-%m-%d %H:%M:%S")] - starting basecalling (${model} model, q-score filter ${qfilter}), using dorado version ${dorado_version}" | \
    tee -a $output_directory/0_basecall.log
    echo -e "[$(date +"%Y-%m-%d %H:%M:%S")] - found ${npod5files} pod5 files" | tee -a $output_directory/0_basecall.log
    echo -e "[$(date +"%Y-%m-%d %H:%M:%S")] - output directory is ${output_directory}" | tee -a $output_directory/0_basecall.log
else
    echo -e "[$(date +"%Y-%m-%d %H:%M:%S")] - starting basecalling (${model} model, q-score filter ${qfilter}) and demultiplexing (${kit}), using dorado version ${dorado_version}" | \
    tee -a $output_directory/0_basecall.log
    echo -e "[$(date +"%Y-%m-%d %H:%M:%S")] - found ${npod5files} pod5 files" | tee -a $output_directory/0_basecall.log
    echo -e "[$(date +"%Y-%m-%d %H:%M:%S")] - output directory is ${output_directory}" | tee -a $output_directory/0_basecall.log
fi
echo "------------------------"

if [[ $demux == 'true' ]]; then # piping is dangerous, so separate basecall and demux
    tempbam=$(mktemp)
    dorado basecaller --min-qscore $qfilter $rec --kit-name $kit --barcode-both-ends $trim $model $podpath > $tempbam &&
    dorado demux $emit --no-classify --output-dir $output_directory $tempbam && \
    rm $tempbam || echo "ERROR: Failed to do basecalling/demultiplexing"
else
    dorado basecaller --min-qscore $qfilter $rec $emit $trim $model $podpath > $output_directory/$outfile
fi

echo "------------------------"
echo "Elapsed time: $SECONDS seconds"
echo "[$(date +"%Y-%m-%d %H:%M:%S")] - finished basecalling of ${npod5files} files, data is in $(realpath $output_directory)" | \
tee -a $output_directory/0_basecall.log
echo "------------------------"

# if we want to mimic the output of MinKNOW realtime basecalling, we have to make a directory for each barcode and put the file there
# in addition the files have to be gzipped
if [ $folders == 'true' -a $demux == 'true' ]; then
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] - moving files to barcode folders" | tee -a $output_directory/0_basecall.log    
    for i in $output_directory/*.fastq; do
        # file name ends in _barcode01.fastq, but can be preceeded by unknown number of fields 
        bc=$(echo $(basename $i) | awk -F "_" '{print $NF}' | cut -d. -f1)
        #bc=$(basename $i .fastq | cut -d_ -f2); 
        bcdir=$(dirname $i)/$bc; 
        mkdir -p $bcdir && mv $i $bcdir/ && pigz $bcdir/*.fastq; 
    done
fi

echo "[$(date +"%Y-%m-%d %H:%M:%S")] - done!" | tee -a $output_directory/0_basecall.log

# clean up
# rm -rf .temp_dorado*

# monitor gpus
# nvidia-smi -l --query-gpu=timestamp,utilization.memory,utilization.gpu --format=csv
