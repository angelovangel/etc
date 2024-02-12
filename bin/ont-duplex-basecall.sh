#! /usr/bin/env bash

# dorado duplex basecall plus optionally demux etc
# dorado duplex > basecall.bam
# samtools view -h -d dx:1 basecall.bam > duplex.bam
# samtools view -h -d dx:0 basecall.bam > simplex.bam

# dorado demux --output-dir basecall-model --kit-name kitname duplex.bam

# IMPORTANT
# ln -s both bin/dorado and lib/lib to /usr/local/bin and /usr/local/lib

usage="$(basename "$0") [-m model] [-p pod5] [-k kit] [-r] [-b] [-f] [-h]

Duplex basecall and optionally demultiplex pod5 files using dorado.
Options:
    -m  (required) dorado model, either fast, hac, or sup
    -p  (required) path to ONT pod5 folder
    -k  (optional) barcoding kit, if used demultiplexing will be performed (SQK-NBD114-96, SQK-RBK114-96 ...)
    -r  (optional flag) find pod5 files recursively
    -b  (optional flag) save reads in bam files, (fastq.gz by default)
    -f  (optional flag) save reads in barcodeXX folders (mimic MinKNOW output)"

recurs=false
bam=false
folders=false
trimmer=false

unset -v model
#unset -v podpath
unset -v kit
#unset -v npod5files

while getopts :hrbfm:p:k: flag
do
   case "${flag}" in
      h) echo "$usage"; exit;;
      m) model=${OPTARG};;
      p) podpath=${OPTARG};;
      k) kit=${OPTARG};;
      r) recurs=true;;
      b) bam=true;;
      f) folders=true;;
      :) printf "missing argument for -%s\n" "$OPTARG" >&2; echo "$usage" >&2; exit 1;;
     \?) printf "illegal option: -%s\n" "$OPTARG" >&2; echo "$usage" >&2; exit 1;;
   esac
done

# check for dorado
if ! command -v dorado > /dev/null 2>&1; then 
    printf "dorado executable not found\n"
    exit 1
else
    dorado_version=$(dorado --version 2>&1) # version is sent to stderr
fi

# check for output directory, make it same level as the main run folder, e.g. parent of pod5 dir
run_directory=$(dirname $podpath)
output_directory=$(dirname $podpath)/duplex-basecall-$model
npod5files=$(find $podpath -name "*.pod5" | wc -l | tr -d ' ') 

[ -d $output_directory ] && \
echo -e "Basecalled folder exists, will be deleted ...\n==============================" &&
rm -rf $output_directory

mkdir -p "$output_directory"


if [[ $recurs == 'true' ]]; then
    rec="-r"
else
    rec=""
fi

if [ -z "$kit" ]; then
    demux=false
else
    demux=true
    bam=true # enforce bam because dorado demux needs it
fi

SECONDS=0
echo "------------------------"
if [[ $demux == 'false' ]]; then
    echo -e "[$(date +"%Y-%m-%d %H:%M:%S")] - starting duplex basecalling (${model} model), using dorado version ${dorado_version}" | \
    tee -a $output_directory/0_basecall.log
    echo -e "[$(date +"%Y-%m-%d %H:%M:%S")] - found ${npod5files} pod5 files" | tee -a $output_directory/0_basecall.log
else
    echo -e "[$(date +"%Y-%m-%d %H:%M:%S")] - starting duplex basecalling (${model} model) and demultiplexing (${kit}), using dorado version ${dorado_version}" | \
    tee -a $output_directory/0_basecall.log
    echo -e "[$(date +"%Y-%m-%d %H:%M:%S")] - found ${npod5files} pod5 files" | tee -a $output_directory/0_basecall.log
fi
echo "------------------------"

# first do dorado duplex, then demux or not

dorado duplex $rec $model $podpath > $output_directory/basecall.bam

if [[ $bam == 'true' ]]; then
    samtools view -h -d dx:1 $output_directory/basecall.bam > $output_directory/duplexreads-$model.bam
    samtools view -h -d dx:0 $output_directory/basecall.bam > $output_directory/simplexreads-$model.bam
else
    samtools view -h -d dx:1 $output_directory/basecall.bam | samtools fastq > $output_directory/duplexreads-$model.fastq
    samtools view -h -d dx:0 $output_directory/basecall.bam | samtools fastq > $output_directory/simplexreads-$model.fastq
fi

# demux the simplex.bam and duplex.bam separately

if [[ $demux == 'true' ]]; then
    dorado demux --output-dir $output_directory/duplex --kit-name $kit --emit-fastq $output_directory/duplexreads-$model.bam && \
    rm $output_directory/duplexreads-$model.bam || echo "ERROR: Failed to do demultiplexing"

    dorado demux --output-dir $output_directory/simplex --kit-name $kit --emit-fastq $output_directory/simplexreads-$model.bam && \
    rm $output_directory/simplexreads-$model.bam || echo "ERROR: Failed to do demultiplexing"
fi

echo "------------------------"
echo "[$(date +"%Y-%m-%d %H:%M:%S")] - finished duplex basecalling of ${npod5files} files, data is in $(realpath $output_directory)" | \
tee -a $output_directory/0_basecall.log
echo "Elapsed time: $SECONDS seconds" | tee -a $output_directory/0_basecall.log
echo "------------------------"

# if we want to mimic the output of MinKNOW realtime basecalling, we have to make a directory for each barcode and put the file there
if [ $folders == 'true' -a $demux == 'true' ]; then
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] - moving files to barcode folders" | tee -a $output_directory/0_basecall.log    
    for i in $output_directory/duplex/*.fastq; do
        bc=$(basename $i .fastq | cut -d_ -f2); 
        bcdir=$(dirname $i)/$bc; 
        mkdir -p $bcdir && mv $i $bcdir/; 
    done

    for i in $output_directory/simplex/*.fastq; do
        bc=$(basename $i .fastq | cut -d_ -f2); 
        bcdir=$(dirname $i)/$bc; 
        mkdir -p $bcdir && mv $i $bcdir/; 
    done

fi

echo "[$(date +"%Y-%m-%d %H:%M:%S")] - done!" | tee -a $output_directory/0_basecall.log