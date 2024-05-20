#! /usr/bin/env bash
# dependencies: pigz, parallel, faster, faster-report.R
# cat, compress, rename fastq files from a fastq_pass based on csv or excel sample-barcode sheet
# runs faster to generate summary data
# optionally runs faster-report to generate html report

# c - a path to a csv or Excel file
# Columns are sample and barcode, in any order
#------------------------
# sample, barcode
# sample1, barcode01
# sample2, barcode02
#------------------------

# p - path to fastq_pass
# option --report can be provided to run faster-report

# r - option to make or not faster-report

# setup
# set -e
usage="$(basename "$0") [-c samplesheet] [-p fastqpath] [-h] [-r]

Process ONT sequencing run - cat, compress, rename fastq files from a fastq_pass folder
based on the samplesheet. Run faster or faster-report on the files. 
Results are saved in 'processed' folder in the current directory.
Options:
    -h  show this help text
    -c  (required) a path to a csv or Excel file with columns 'sample' and 'barcode', in any order
    -p  (required) path to ONT fastq_pass folder
    -r  (optional flag) generate faster-report html file
    -d  (optional flag) use docker to generate faster-report.html. Use only together with the -r option.
    -n  (optional) non-barcoded run - use barcode00 in samplesheet"

makereport=false
usedocker=false
nonbc=false

while getopts :hrdnc:p: flag
do
   case "${flag}" in
      h) echo "$usage"; exit;;
      c) infile=${OPTARG};;
      p) fastqpath=${OPTARG};;
      r) makereport=true;;
      n) nonbc=true;;
      d) usedocker=true;;
      :) printf "missing argument for -%s\n" "$OPTARG" >&2; echo "$usage" >&2; exit 1;;
     \?) printf "illegal option: -%s\n" "$OPTARG" >&2; echo "$usage" >&2; exit 1;;
   esac
done

# mandatory arguments
if [ ! "$infile" ] || [ ! "$fastqpath" ]; then
  echo "arguments -c and -p must be provided"
  echo "$usage" >&2; exit 1
fi

if [[ ! -f ${infile} ]] || [[ ! -d ${fastqpath} ]]; then
    echo "File ${infile} or ${fastqpath} does not exist" >&2
    exit 2
fi

# convert to csv if excel is provided
infile_ext=${infile##*.}
if [ ${infile##*.} == 'xlsx' ]; then
    echo 'Excel file provided, will be converted to csv ...'
    excel2csv.R $infile &&
    #csvfile=$(basename $infile .$infile_ext).csv && 
    csvfile=$(dirname $infile)/$(basename $infile .$infile_ext).csv
    echo -e "CSV file generated ==> ${csvfile} \n================================================================" ||
    echo 'Converting Excel to csv failed...!'
else
    echo -e 'CSV file provided...\n================================================================'
    csvfile=$infile
fi

# place processed in parent folder of $fastqpath
processed=$(dirname $fastqpath)/processed

[ -d $processed ] && \
echo -e "Processed folder exists, will be deleted ...\n================================================================" && \
rm -rf $processed
mkdir -p $processed/fastq
cp $csvfile $processed/samplesheet.csv # make a copy of the sample sheet

# get col indexes
samplename_idx=$(head -1 ${csvfile} | sed 's/,/\n/g' | nl | grep -E 'S|sample' | cut -f 1)
barcode_idx=$(head -1 ${csvfile} | sed 's/,/\n/g' | nl | grep -E 'B|barcode' | cut -f 1)

# check samplesheet is valid
num='[0-9]+'
if  [[ ! $samplename_idx =~ $num ]] || [[ ! $barcode_idx =~ $num ]]; then
    echo "Samplesheet is not valid, check that columns 'sample' and 'barcode' exist" >&2
    exit 2
fi

# if non-barcoded, mv fastq files in barcode00 and proceed as ususal
if [[ $nonbc == 'true' ]] && [[ $(ls -A $fastqpath/*.fastq.gz) ]]; then
    echo -e "Non-barcoded run, will create $fastqpath/barcode00 directory...\n================================================================"
    mkdir -p $fastqpath/barcode00 && mv $fastqpath/*.fastq.gz $fastqpath/barcode00/
elif [[ $nonbc == 'true' ]]; then
    echo -e "Non-barcoded run selected, but no fastq files found in $fastqpath \n================================================================"
    exit 0
fi

counter=0
while IFS="," read line; do
    [ -z "$line" ] && continue # skip empty lines
    samplename=$(echo $line | cut -f $samplename_idx -d, | tr -d " " | tr -d '\r') # also trim white spaces from sample names
    barcode=$(echo $line | cut -f $barcode_idx -d, | tr -d " " | tr -d '\r') # also trim white spaces from bc names
    currentdir=$fastqpath/$barcode
    # skip header and if barcode or sample is NA 
    if [[ $barcode == 'barcode' ]] || [[ $barcode == 'NA' ]] || [[ $samplename == 'NA' ]]; then
        echo "skipping $line"
        continue
    fi
    pigz -q $currentdir/*.* #in case these are fastq files
    ((counter++)) # counter to add to sample name
    prefix=$(printf "%02d" $counter) # prepend zero
    # check if dir exists and has files and cat
    [ -d $currentdir ] && 
    [ "$(ls -A $currentdir)" ] && 
    echo "merging ${samplename} ----- ${barcode}" && 
    cat $currentdir/*.fastq.gz > $processed/fastq/${prefix}_${samplename}.fastq.gz ||
    echo folder $currentdir not found or empty!
done < $csvfile

nsamples=$(ls -A $processed/fastq/*.fastq.gz | wc -l)
[ "$(ls -A $processed/fastq/*.fastq.gz)" ] &&
echo -e '================================================================' &&
echo "Running faster on $nsamples samples ..." && 
echo -e '================================================================' &&
echo -e "file\treads\tbases\tn_bases\tmin_len\tmax_len\tmean_len\tQ1\tQ2\tQ3\tN50\tQ20_percent\tQ30_percent" > $processed/fastq-stats.tsv &&
parallel -k faster -ts ::: $processed/fastq/*.fastq.gz >> $processed/fastq-stats.tsv || 
echo "No fastq files found"


if [[ $makereport == 'true' ]] && [[ $(command -v faster-report.R) ]] && [[ $usedocker != 'true' ]]; then
    [ "$(ls -A $processed/fastq/*.fastq.gz)" ] &&
    echo -e 'Running faster-report.R ...\n================================================================' && 
    faster-report.R -p $(realpath $processed/fastq) &&
    mv faster-report.html $processed/faster-report.html ||
    echo "faster-report failed!"
fi

if [[ $makereport == 'true' ]] && [[ $usedocker == 'true' ]]; then
    [ "$(ls -A $processed/fastq/*.fastq.gz)" ] &&
    echo -e 'Running docker image aangeloo/faster-report ...\n================================================================'
    docker run -it \
        --mount type=bind,src="$HOME",target="$HOME" \
        -w $(realpath $processed) \
        aangeloo/faster-report \
        -p $(realpath $processed/fastq) 
fi


echo -e "================================================================\nDone!"

