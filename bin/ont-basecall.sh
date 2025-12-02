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
    -l  (optional) path to adaptive sampling decision file (with columns read_id, action, action_response). Only reads with 'action == sequence' will be basecalled.
    -r  (optional flag) find pod5 files recursively
    -b  (optional flag) save reads in bam files, (fastq.gz by default)
    -t  (optional flag) trim all adapters, primers and barcodes
    -q  (optional) filter by minimum read q-score (default 10)"

recurs=false
bam=false
trimmer=false # MinKNOW is trimm OFF by default, in dorado is default ON
qfilter=10

unset -v model
unset -v podpath
unset -v kit

timestamp() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")]"
}

while getopts :hrbtm:p:k:l:q: flag
do
   case "${flag}" in
      h) echo "$usage"; exit;;
      m) model=${OPTARG};;
      p) podpath=${OPTARG};;
      k) kit=${OPTARG};;
      l) decisionfile=${OPTARG};;
      r) recurs=true;;
      b) bam=true;;
      t) trimmer=true;;
      q) qfilter=${OPTARG};;
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
echo -e "Basecalled folder exists, will be deleted ...\n==============================" && \
rm -rf $output_directory
# read -p "Continue (y/n)?" choice
# case "$choice" in 
#   y|Y ) rm -rf $output_directory;;
#   n|N ) echo "Exiting.." && exit 1;;
#   * ) echo "Creating output directory: $(realpath $output_directory)";;
# esac

npod5files=$(find $podpath -name "*.pod5" | wc -l | tr -d ' ')

mkdir -p "$output_directory"

if [[ $bam == 'true' ]]; then
    outfile="reads.bam"
    emit=""
else
    outfile="reads.fastq"
    emit="--emit-fastq"
fi

if [[ $recurs == 'true' ]]; then
    rec="-r"
else
    rec=""
fi

if [[ $trimmer == 'true' ]]; then
    trim="--trim all" # default on in dorado
else
    trim="--no-trim"
fi

if [ -z "$kit" ]; then
    demux=false
else
    demux=true
fi

if [ -z "$decisionfile" ]; then
    read_ids=""
else    
    echo -e "$(timestamp) - filtering adaptive sampling reads" | tee -a $output_directory/0_basecall.log
    awk -F',' '$2 == "sequence"' $decisionfile | cut -f1 -d, > $output_directory/0_reads_to_basecall.txt
    nreads_bc=$(wc -l < $output_directory/0_reads_to_basecall.txt)
    nreads_total=$(wc -l < $decisionfile)
    echo -e "$(timestamp) - found $nreads_bc (out of $nreads_total) reads to basecall " | tee -a $output_directory/0_basecall.log
    read_ids="--read-ids $output_directory/0_reads_to_basecall.txt"
fi

SECONDS=0
echo "------------------------"
if [[ $demux == 'false' ]]; then
    echo -e "$(timestamp) - starting basecalling (${model} model, q-score filter ${qfilter}), using dorado version ${dorado_version}" | \
    tee -a $output_directory/0_basecall.log
    echo -e "$(timestamp) - found ${npod5files} pod5 files" | tee -a $output_directory/0_basecall.log
    echo -e "$(timestamp) - output directory is ${output_directory}" | tee -a $output_directory/0_basecall.log
else
    echo -e "$(timestamp) - starting basecalling (${model} model, q-score filter ${qfilter}) and demultiplexing (${kit}), using dorado version ${dorado_version}" | \
    tee -a $output_directory/0_basecall.log
    echo -e "$(timestamp) - found ${npod5files} pod5 files" | tee -a $output_directory/0_basecall.log
    echo -e "$(timestamp) - output directory is ${output_directory}" | tee -a $output_directory/0_basecall.log
fi
echo "------------------------"

if [[ $demux == 'true' ]]; then # piping is dangerous, so separate basecall and demux
    # since dorado v1.3.0 basecaller produces the MinKNOW output with --output-dir and --kit-name
    # tempbam=$(mktemp)
    dorado basecaller --min-qscore $qfilter $rec $emit --kit-name $kit $trim $read_ids --output-dir $output_directory $model $podpath
    # dorado demux $emit --no-classify --output-dir $output_directory $tempbam && \
    # echo -e $(timestamp) - bam head: $(samtools head $tempbam | grep "@PG") | tee -a $output_directory/0_basecall.log && \
    
else
    dorado basecaller --min-qscore $qfilter $rec $emit $trim $read_ids $model $podpath > $output_directory/$outfile
fi

echo "------------------------"
echo "Elapsed time: $SECONDS seconds"
echo "$(timestamp) - finished basecalling of ${npod5files} files, data is in $(realpath $output_directory)" | \
tee -a $output_directory/0_basecall.log
echo "------------------------"

### This is now handled by dorado since v1.3.0

# if we want to mimic the output of MinKNOW realtime basecalling, we have to make a directory for each barcode and put the file there
# in addition the files have to be gzipped
# if [ $folders == 'true' -a $demux == 'true' ]; then
#     echo "$(timestamp) - moving files to barcode folders" | tee -a $output_directory/0_basecall.log    
#     for i in $output_directory/*.fastq; do
#         # file name ends in _barcode01.fastq, but can be preceeded by unknown number of fields 
#         bc=$(echo $(basename $i) | awk -F "_" '{print $NF}' | cut -d. -f1)
#         #bc=$(basename $i .fastq | cut -d_ -f2); 
#         bcdir=$(dirname $i)/$bc; 
#         mkdir -p $bcdir && mv $i $bcdir/ && pigz $bcdir/*.fastq; 
#     done
# fi

### This is now handled by dorado since v1.3.0

echo "$(timestamp) - done!" | tee -a $output_directory/0_basecall.log

# clean up
# rm -rf .temp_dorado*

# monitor gpus
# nvidia-smi -l --query-gpu=timestamp,utilization.memory,utilization.gpu --format=csv
