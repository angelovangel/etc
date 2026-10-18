#! /usr/bin/env bash
# dependencies: utag (+ barbell), parallel, faster, nextflow (for -r)
# demultiplex custom utag (CDI/UDI) amplicon libraries with 'utag demux' and lay out the results
# like ont-process-run.sh: processed/fastq/<sample>.fastq.gz, processed/samplesheet.*,
# processed/fastq-stats.tsv and optionally processed/faster-report.html
# utag's summary files (summary.tsv, unexpected.tsv, run_summary.csv, utag.log, inspect.txt) are kept
# in processed/utag (barbell/ intermediates are deleted), and a plate heatmap of reads per well is written to processed/plates.html

# p - path to the reads: fastq_pass, demux, combined or a single barcodeNN folder (searched recursively)
# c - (optional) samplesheet csv or xlsx, see 'utag demux -h'
#------------------------
# sample,plate,well
# Soil_A,1,A1
#------------------------
# without -c every plate-map well is a sample (Plate1-A1 ...)
# everything after -- is passed to utag demux, e.g. -- -c nbd --ont-barcode NB01 -t 16

# setup
# set -e
usage="$(basename "$0") [-p fastqpath] [-c samplesheet] [-h] [-r] [-s subsample] [-- utag demux options]

Demultiplex utag amplicon libraries with 'utag demux', then cat/rename the per-sample fastq files
and run faster or faster-report on them, like ont-process-run.sh.
Results are saved in 'processed' next to fastqpath (for a barcodeNN folder: 'processed-barcodeNN'
in the run folder).
Options:
    -h  show this help text
    -p  (required) path to fastq_pass, demux, combined or a barcodeNN folder (searched recursively)
    -c  (optional) csv or Excel file with columns 'sample','plate','well' (or 'sample','utag-fwd','utag-rev')
    -r  (optional flag) generate faster-report html file
    -s  (optional) subsample fastq files for html report gc, len, qscore and kmer calculations (default: 0.1, can be 0.1 to 1.0)
    --  options after this are passed to 'utag demux' (e.g. -c nbd --ont-barcode NB01 -t 16), not -r/-o/--samplesheet"

makereport=false
subs=0.1

while getopts :hrc:p:s: flag
do
   case "${flag}" in
      h) echo "$usage"; exit;;
      c) infile=${OPTARG};;
      p) fastqpath=${OPTARG%/};;
      r) makereport=true;;
      s) subs=${OPTARG};;
      :) printf "missing argument for -%s\n" "$OPTARG" >&2; echo "$usage" >&2; exit 1;;
     \?) printf "illegal option: -%s\n" "$OPTARG" >&2; echo "$usage" >&2; exit 1;;
   esac
done
shift $((OPTIND - 1))
[ "$1" == '--' ] && shift
# remaining "$@" are utag demux options

# mandatory arguments
if [ ! "$fastqpath" ]; then
  echo "argument -p must be provided"
  echo "$usage" >&2; exit 1
fi

if [[ ! -d ${fastqpath} ]] || { [ "$infile" ] && [[ ! -f ${infile} ]]; }; then
    echo "File ${infile} or directory ${fastqpath} does not exist" >&2
    exit 2
fi

for bin in utag faster parallel; do
    if ! command -v $bin > /dev/null; then
        echo "$bin not found on PATH" >&2
        exit 2
    fi
done

if [ -z "$(find "$fastqpath" -type f \( -name '*.fastq' -o -name '*.fastq.gz' -o -name '*.fq' -o -name '*.fq.gz' \) | head -1)" ]; then
    echo "Could not find any fastq files in $fastqpath" >&2
    exit 2
fi

# place processed in parent folder of $fastqpath, as ont-process-run.sh does;
# a barcodeNN folder sits inside fastq_pass, so use processed-barcodeNN in the run folder instead
if [[ $(basename "$fastqpath") =~ ^barcode[0-9]+$ ]]; then
    processed=$(dirname "$(dirname "$fastqpath")")/processed-$(basename "$fastqpath")
else
    processed=$(dirname "$fastqpath")/processed
fi

[ -d "$processed" ] && \
echo -e "Processed folder exists, will be deleted ...\n================================================================" && \
rm -rf "$processed"
mkdir -p "$processed/fastq"

# redirect all output to log file and terminal
exec > >(tee "$processed/.ont-process-utag.log") 2>&1

echo -e "Reads folder: $fastqpath\nResults: $processed\n================================================================"

samplesheet_args=()
if [ "$infile" ]; then
    cp "$infile" "$processed/samplesheet.${infile##*.}" # make a copy of the sample sheet
    samplesheet_args=(--samplesheet "$infile")
else
    echo -e "No samplesheet, every plate-map well is a sample...\n================================================================"
fi

# RStudio/Shiny set CLICOLOR_FORCE=1; barbell then writes ANSI codes into its output files
unset CLICOLOR_FORCE FORCE_COLOR

# utag writes to a temp folder next to processed; only its summary files are kept, barbell/ is deleted
utag_tmp=$(mktemp -d "$(dirname "$processed")/.utag-tmp-XXXXXX")
trap 'rm -rf "$utag_tmp"' EXIT INT TERM

echo -e "Running utag demux ...\n================================================================"
if ! utag demux --color never --gzip -r "$fastqpath" -o "$utag_tmp" "${samplesheet_args[@]}" "$@"; then
    echo "utag demux failed!" >&2
    exit 1
fi

# per-sample files to processed/fastq, like ont-process-run.sh (utag writes no file for 0-read samples)
if compgen -G "$utag_tmp/samples/*.fastq.gz" > /dev/null; then
    mv "$utag_tmp"/samples/*.fastq.gz "$processed/fastq/"
fi
mkdir -p "$processed/utag"
for f in summary.tsv unexpected.tsv run_summary.csv utag.log barbell/inspect.txt; do
    [ -f "$utag_tmp/$f" ] && mv "$utag_tmp/$f" "$processed/utag/"
done
rm -rf "$utag_tmp"

nsamples=$(find "$processed/fastq" -name '*.fastq.gz' | wc -l | tr -d ' ')
[ "$nsamples" -gt 0 ] &&
echo -e '================================================================' &&
echo "Running faster on $nsamples samples ..." &&
echo -e '================================================================' &&
echo -e "file\treads\tbases\tn_bases\tmin_len\tmax_len\tmean_len\tQ1\tQ2\tQ3\tN50\tQ20_percent\tQ30_percent" > "$processed/fastq-stats.tsv" &&
parallel -k faster -ts ::: "$processed"/fastq/*.fastq.gz >> "$processed/fastq-stats.tsv" ||
echo "No fastq files found"

# plate heatmap of reads per well (plate-heatmap.py ships next to utag.py)
utag_dir=$(dirname "$(realpath "$(command -v utag)")")
if [ -f "$utag_dir/plate-heatmap.py" ] && [ -f "$processed/utag/summary.tsv" ]; then
    echo -e '================================================================\nWriting plate heatmap ...'
    python3 "$utag_dir/plate-heatmap.py" "$processed/utag/summary.tsv" -o "$processed/plates.html" ||
    echo "plate heatmap failed!"
fi

if [[ $makereport == 'true' ]]; then
    if [ "$nsamples" -gt 0 ]; then
        echo -e 'Running nextflow ...\n================================================================'
        nf_temp=$(mktemp -d)
        reads_abs=$(realpath "$processed/fastq")
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
