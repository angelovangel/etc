#! /usr/bin/env bash
# re-basecall with dorado in a tmux

# IMPORTANT
# ln -s both bin/dorado and lib/lib to /usr/local/bin and use /usr/local/lib

usage="$(basename "$0") [-m model] [-p pod5] [-k kit] [-r] [-b] [-h]

Basecall and optionally demultiplex pod5 files using dorado.
Options:
    -m  (required) dorado model, either fast, hac, or sup
    -p  (required) path to ONT pod5 folder
    -k  (optional) barcoding kit, if used demultiplexing will be performed (SQK-NBD114-96, SQK-RBK114-96 ...)
    -r  (optional flag) find pod5 files recursively
    -b  (optional flag) save reads in bam files, (fastq.gz by default)"

recurs=false
bam=false

unset -v model
unset -v podpath
unset -v kit

while getopts :hrbm:p:k: flag
do
   case "${flag}" in
      h) echo "$usage"; exit;;
      m) model=${OPTARG};;
      p) podpath=${OPTARG};;
      k) kit=${OPTARG};;
      r) recurs=true;;
      b) bam=true;;
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
output_directory=$(dirname $podpath)/basecalled-$model

[ -d $output_directory ] && \
echo -e "Basecalled folder exists, will be deleted ...\n==============================" && \
read -p "Continue (y/n)?" choice
case "$choice" in 
  y|Y ) rm -rf $output_directory;;
  n|N ) echo "Exiting.." && exit 1;;
  * ) echo "Creating output directory: $(realpath $output_directory)";;
esac

mkdir -p "$output_directory"

if [[ $bam == 'true' ]]; then
    outfile="reads-$model.bam"
    emit=""
else
    outfile="reads-$model.fastq"
    emit="--emit-fastq"
fi

if [[ $recurs == 'true' ]]; then
    rec="-r"
else
    rec=""
fi

if [ -z "$kit" ]; then
    demux=false
else
    demux=true
fi

SECONDS=0
echo "------------------------"
if [[ $demux == 'false' ]]; then
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] - starting basecalling (${model} model), using dorado version ${dorado_version}" | \
    tee -a dorado-basecall.log
else
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] - starting basecalling (${model} model) and demultiplexing (${kit}), using dorado version ${dorado_version}" | \
    tee -a dorado-basecall.log
fi
echo "------------------------"

if [[ $demux == 'true' ]]; then
    dorado basecaller --min-qscore 7 $rec --kit-name $kit --barcode-both-ends --trim 'adapters' $model $podpath | \
    dorado demux $emit --no-classify --output-dir $output_directory
else
    dorado basecaller --min-qscore 7 $rec $emit --trim 'adapters' $model $podpath > $output_directory/$outfile
fi

echo "------------------------"
echo "Elapsed time: $SECONDS seconds"
echo "[$(date +"%Y-%m-%d %H:%M:%S")] - finished basecalling, data is in $(realpath $output_directory)" | \
tee -a dorado-basecall.log
echo "------------------------"
# clean up
# rm -rf .temp_dorado*

# monitor gpus
# nvidia-smi -l --query-gpu=timestamp,utilization.memory,utilization.gpu --format=csv
