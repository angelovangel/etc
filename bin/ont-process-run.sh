#! /usr/bin/env bash
# dependencies: pigz, parallel, faster, faster-report.R, samtools
# cat, compress, rename fastq files from a fastq_pass based on csv or excel sample-barcode sheet
# runs faster to generate summary data
# optionally runs faster-report to generate html report
# fastq vs bam mode is auto-detected by inspecting the fastq_pass/bam_pass folder (no -b flag
# needed) - files are merged per sample with 'samtools merge' (no fastq conversion) in bam mode.
# faster-report accepts bam files directly; faster itself needs fastq, so bam is streamed to it
# on the fly via 'samtools fastq'

# c - a path to a csv or Excel file
# Columns are sample and barcode, in any order
#------------------------
# sample, barcode
# sample1, barcode01
# sample2, barcode02
#------------------------

# p - path to fastq_pass (or bam_pass if -b is used)
# option --report can be provided to run faster-report

# r - option to make or not faster-report

# setup
# set -e
usage="$(basename "$0") [-c samplesheet] [-p fastqpath] [-h] [-r]

Process ONT sequencing run - cat, compress, rename fastq files from a fastq_pass folder
based on the samplesheet. Run faster or faster-report on the files. 
Results are saved in 'processed' folder in the current directory.
fastq vs bam mode is detected automatically from the files found in fastqpath.
Options:
    -h  show this help text
    -c  (required) a path to a csv or Excel file with columns 'sample' and 'barcode', in any order
    -p  (required) path to ONT fastq_pass folder (or bam_pass folder - auto-detected)
    -r  (optional flag) generate faster-report html file
    -s  (optional) subsample fastq/bam files for html report gc, len, qscore and kmer calculations (default: 0.1, can be 0.1 to 1.0)
    -n  (optional) non-barcoded run - use barcode00 in samplesheet"

makereport=false
nonbc=false
subs=0.1

while getopts :hrnc:p:s: flag
do
   case "${flag}" in
      h) echo "$usage"; exit;;
      c) infile=${OPTARG};;
      p) fastqpath=${OPTARG};;
      r) makereport=true;;
      s) subs=${OPTARG};;
      n) nonbc=true;;
      :) printf "missing argument for -%s\n" "$OPTARG" >&2; echo "$usage" >&2; exit 1;;
     \?) printf "illegal option: -%s\n" "$OPTARG" >&2; echo "$usage" >&2; exit 1;;
   esac
done

# instread of having to supply samplesheet in nonbc runs, just make it here
# use -c to give samples name
if [ $nonbc == 'true' ]; then
    temp_file=$(mktemp)
    mv $temp_file $temp_file.csv
    echo "sample,barcode" > $temp_file.csv
    echo "$infile,barcode00" >> $temp_file.csv
    infile=$temp_file.csv
fi

# mandatory arguments
if [ ! "$infile" ] || [ ! "$fastqpath" ]; then
  echo "arguments -c and -p must be provided"
  echo "$usage" >&2; exit 1
fi

if [[ ! -f ${infile} ]] || [[ ! -d ${fastqpath} ]]; then
    echo "File ${infile} or directory ${fastqpath} does not exist" >&2
    exit 2
fi

# auto-detect fastq vs bam mode by looking at fastqpath - either files directly inside it
# (non-barcoded run) or inside its first barcode* subfolder
detect_filetype() {
    local path=$1
    if compgen -G "$path/*.bam" > /dev/null; then
        echo bam; return
    fi
    if compgen -G "$path/*.fastq.gz" > /dev/null; then
        echo fastq; return
    fi
    local firstdir
    firstdir=$(find "$path" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | head -1)
    if [ -n "$firstdir" ]; then
        if compgen -G "$firstdir/*.bam" > /dev/null; then
            echo bam; return
        fi
        if compgen -G "$firstdir/*.fastq.gz" > /dev/null; then
            echo fastq; return
        fi
    fi
    echo none
}

filetype=$(detect_filetype "$fastqpath")
case "$filetype" in
    bam)  bammode=true ;;
    fastq) bammode=false ;;
    *)
        echo "Could not find any .fastq.gz or .bam files in $fastqpath (or its first subfolder)" >&2
        exit 2
        ;;
esac

# set glob/extension/output-dir depending on detected mode
if [[ $bammode == 'true' ]]; then
    ext='bam'
    globpat='*.bam'
    outdir='bam'
    echo -e "Detected bam files, running in bam mode...\n================================================================"
else
    ext='fastq.gz'
    globpat='*.fastq.gz'
    outdir='fastq'
    echo -e "Detected fastq.gz files, running in fastq mode...\n================================================================"
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

# make sure csvfile has a trailing newline
if [ -n "$(tail -c 1 "$csvfile")" ]; then
    echo "" >> "$csvfile"
fi

# place processed in parent folder of $fastqpath
processed=$(dirname $fastqpath)/processed

[ -d $processed ] && \
echo -e "Processed folder exists, will be deleted ...\n================================================================" && \
rm -rf $processed
mkdir -p $processed/$outdir
cp $csvfile $processed/samplesheet.csv # make a copy of the sample sheet

# redirect all output to log file and terminal
exec > >(tee "$processed/.ont-process-run.log") 2>&1

# get col indexes
samplename_idx=$(head -1 "${csvfile}" | tr -d '"\r' | sed 's/,/\n/g' | nl | grep -iE '^\s*[0-9]+\s+sample$' | cut -f 1 | head -1)
barcode_idx=$(head -1 "${csvfile}" | tr -d '"\r' | sed 's/,/\n/g' | nl | grep -iE '^\s*[0-9]+\s+barcode$' | cut -f 1 | head -1)

# check samplesheet is valid
num='[0-9]+'
if  [[ ! $samplename_idx =~ $num ]] || [[ ! $barcode_idx =~ $num ]]; then
    echo "Samplesheet is not valid, check that columns 'sample' and 'barcode' exist" >&2
    exit 2
fi

# if non-barcoded, mv fastq/bam files in barcode00 and proceed as ususal
if [[ $nonbc == 'true' ]] && [[ $(ls -A $fastqpath/$globpat) ]]; then
    echo -e "Non-barcoded run, will create $fastqpath/barcode00 directory...\n================================================================"
    mkdir -p $fastqpath/barcode00 && mv $fastqpath/$globpat $fastqpath/barcode00/
elif [[ $nonbc == 'true' ]]; then
    echo -e "Non-barcoded run selected, but no $ext files found in $fastqpath \n================================================================"
    exit 0
fi

counter=0
while IFS="," read line; do
    [ -z "$line" ] && continue # skip empty lines
    samplename=$(echo $line | cut -f $samplename_idx -d, | tr -d '"' | tr -d " " | tr -d '\r') # also trim white spaces from sample names
    barcode=$(echo $line | cut -f $barcode_idx -d, | tr -d '"' | tr -d " " | tr -d '\r') # also trim white spaces from bc names
    currentdir=$fastqpath/$barcode
    # skip header and if barcode or sample is NA or empty!
    # [[ -z "${var//[[:space:]]/}" ]] is used to check if barcode is empty or contains only spaces
    if [[ $barcode == 'barcode' ]] || [[  -z "${barcode//[[:space:]]/}" ]] || [[ $barcode == 'NA' ]] || [[ $samplename == 'NA' ]]; then
        echo "skipping $line"
        continue
    fi
    if [[ $bammode == 'false' ]] && compgen -G "$currentdir/*" > /dev/null; then
        pigz -q $currentdir/*.* #in case these are fastq files
    fi
    ((counter++)) # counter to add to sample name
    prefix=$(printf "%02d" $counter) # prepend zero
    # check if dir exists and has matching files, then merge (cat for fastq, samtools merge for bam);
    # skip cleanly (no output file at all) when there are no matching files, instead of writing an
    # empty file
    if [[ $bammode == 'true' ]]; then
        outfile=$processed/$outdir/${samplename}.bam
        if [ -d $currentdir ] && compgen -G "$currentdir/*.bam" > /dev/null; then
            echo "merging ${samplename} ----- ${barcode}"
            samtools merge -f "$outfile" $currentdir/*.bam
            [ -s "$outfile" ] || { echo "merge produced no data, removing empty $outfile"; rm -f "$outfile"; }
        else
            echo "folder $currentdir not found or has no bam files, skipping!"
        fi
    else
        outfile=$processed/fastq/${samplename}.fastq.gz
        if [ -d $currentdir ] && compgen -G "$currentdir/*.fastq.gz" > /dev/null; then
            echo "merging ${samplename} ----- ${barcode}"
            cat $currentdir/*.fastq.gz > "$outfile"
            [ -s "$outfile" ] || { echo "merge produced no data, removing empty $outfile"; rm -f "$outfile"; }
        else
            echo "folder $currentdir not found or has no fastq.gz files, skipping!"
        fi
    fi
done < $csvfile

# if non-barcoded, repair the barcode00 back to original
if [[ $nonbc == 'true' ]] && [[ $(ls -A $fastqpath/barcode00/$globpat) ]]; then
    echo -e "Non-barcoded run, will move files in $fastqpath/barcode00 back...\n================================================================"
    mv $fastqpath/barcode00/$globpat $fastqpath/ && rm -r $fastqpath/barcode00
fi

if [[ $bammode == 'true' ]]; then
    # faster needs fastq input, so stream each merged bam through 'samtools fastq' on the fly,
    # then fix up the file-name column (which would otherwise show /dev/stdin) to the sample name
    faster_from_bam() {
        local bamfile=$1
        local samplename=$(basename "$bamfile" .bam)
        samtools fastq "$bamfile" 2>/dev/null | faster -ts /dev/stdin | awk -v s="$samplename" 'BEGIN{OFS="\t"} {$1=s; print}'
    }
    export -f faster_from_bam
    nsamples=$(ls -A $processed/bam/*.bam | wc -l)
    [ "$(ls -A $processed/bam/*.bam)" ] &&
    echo -e '================================================================' &&
    echo "Running faster (via samtools fastq) on $nsamples samples ..." &&
    echo -e '================================================================' &&
    echo -e "file\treads\tbases\tn_bases\tmin_len\tmax_len\tmean_len\tQ1\tQ2\tQ3\tN50\tQ20_percent\tQ30_percent" > $processed/fastq-stats.tsv &&
    parallel -k faster_from_bam ::: $processed/bam/*.bam >> $processed/fastq-stats.tsv ||
    echo "No bam files found"
else
    nsamples=$(ls -A $processed/fastq/*.fastq.gz | wc -l)
    [ "$(ls -A $processed/fastq/*.fastq.gz)" ] &&
    echo -e '================================================================' &&
    echo "Running faster on $nsamples samples ..." && 
    echo -e '================================================================' &&
    echo -e "file\treads\tbases\tn_bases\tmin_len\tmax_len\tmean_len\tQ1\tQ2\tQ3\tN50\tQ20_percent\tQ30_percent" > $processed/fastq-stats.tsv &&
    parallel -k faster -ts ::: $processed/fastq/*.fastq.gz >> $processed/fastq-stats.tsv || 
    echo "No fastq files found"
fi


if [[ $makereport == 'true' ]]; then
    if [ "$(ls -A $processed/$outdir/$globpat)" ]; then
        echo -e 'Running nextflow ...\n================================================================'
        nf_temp=$(mktemp -d)
        reads_abs=$(realpath "$processed/$outdir")
        processed_abs=$(realpath "$processed")
        echo -e "nextflow run angelovangel/faster-report --reads $reads_abs --subsample $subs\n-----------------"
        if ( cd "$nf_temp" && nextflow run angelovangel/faster-report --reads "$reads_abs" --subsample $subs); then
            cp "$nf_temp/output/faster-report.html" "$processed_abs/"
            rm -rf "$nf_temp"
        else
            echo "nextflow faster-report failed!"
            rm -rf "$nf_temp"
        fi
    fi
fi

echo -e "================================================================\nDone!"

