#! /usr/bin/env bash

# cat, compress, rename fastq files from a fastq_pass based on csv sample-barcode sheet
# runs faster (required dependency) to generate summary data

# c - a path to csv file
# ',' separated csv file with unix line endings. Columns are sample and barcode, in any order
#------------------------
# sample, barcode
# sample1, barcode01
# sample2, barcode02
#------------------------

# p - path to fastq_pass
# option --report can be provided to run faster-report

# r - option to make or not faster-report

# setup
makereport=false

while getopts c:p:r flag
do
   case "${flag}" in
      c) csvfile=${OPTARG};;
      p) fastqpath=${OPTARG};;
      r) makereport=true;;
      ?) printf "Usage: %s -c samplesheet.csv -p fastq_pass -r \n" $0
         exit 2;;
   esac
done

shift "$(( OPTIND - 1 ))"

if [[ ! -f ${csvfile} ]] || [[ ! -d ${fastqpath} ]]; then
    echo "File ${csvfile} or ${fastqpath} does not exist" >&2
    exit 2
fi

[ -d processed ] && \
echo "Results folder exists, will be deleted ..." && \
rm -rf processed
mkdir -p processed/fastq
cp $csvfile processed/samplesheet.csv # make a copy of the sample sheet

# get col indexes
samplename_idx=$(head -1 ${csvfile} | sed 's/,/\n/g' | nl | grep -E 'S|sample' | cut -f 1)
barcode_idx=$(head -1 ${csvfile} | sed 's/,/\n/g' | nl | grep -E 'B|barcode' | cut -f 1)

# check samplesheet is valid
num='[0-9]+'
if  [[ ! $samplename_idx =~ $num ]] || [[ ! $barcode_idx =~ $num ]]; then
    echo "Samplesheet is not valid, check that columns 'sample' and 'barcode' exist" >&2
    exit 2
fi

counter=0
while IFS="," read line; do
    samplename=$(echo $line | cut -f $samplename_idx -d,)
    barcode=$(echo $line | cut -f $barcode_idx -d,)
    currentdir=${fastqpath}/${barcode// /}
    # skip header and if barcode or sample is NA 
    if [[ $barcode == 'barcode' ]] || [[ $barcode == 'NA' ]] || [[ $samplename == 'NA' ]]; then
        echo "skipping $line"
        continue
    fi
    ((counter++)) # counter to add to sample name
    prefix=$(printf "%02d" $counter) # prepend zero
    # check if dir exists and has files and cat
    [ -d $currentdir ] && 
    [ "$(ls -A $currentdir)" ] && 
    echo "merging ${samplename} ----- ${barcode}" && 
    cat $currentdir/*.fastq.gz > processed/fastq/${prefix}_${samplename}.fastq.gz ||
    echo folder ${currentdir} not found or empty!
done < $csvfile


if [[ $makereport == 'true' ]] && [[ $(command -v faster-report.R) ]]; then
    [ "$(ls -A processed/fastq/*.fastq.gz)" ] && 
    faster-report.R -p $(realpath processed/fastq) &&
    mv faster-report.html processed/faster-report.html ||
    echo "No fastq files found"
else
    nsamples=$(ls -A processed/fastq/*.fastq.gz | wc -l)
    [ "$(ls -A processed/fastq/*.fastq.gz)" ] && 
    echo "Running faster on $nsamples samples ..." && 
    echo -e "file\treads\tbases\tn_bases\tmin_len\tmax_len\tmean_len\tQ1\tQ2\tQ3\tN50\tQ20_percent\tQ30_percent" > processed/fastq-stats.tsv &&
    parallel -k faster -ts ::: processed/fastq/*.fastq.gz >> processed/fastq-stats.tsv || 
    echo "No fastq files found"
fi

echo "Done!"

