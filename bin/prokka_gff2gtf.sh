#!/usr/bin/env bash

# convert a GFF file generated by PROKKA to a GTF file compatible with nf-core/rnaseq,
# and for gtf2bed (for geneBody_coverage.py)
# gtf2bed wants "exon" as a key!!
# only rRNA and tRNA "exons" get analysed by nf-core/rnaseq!! Check files after running it
#
# the input has to have .gff extension

# uses getopts to decide if to replace all "transcript" keys with "exon"

no_args="true" # to capture case where no arguments were used and exit gracefully
exon="no" # if no -e option used
usage()
{
  echo "Usage: prokka_gff2gtf.sh [options]"
  echo "For help, try:"
  echo "prokka_gff2gtf -h"
}

while getopts ":ehi:" opt; do
  case ${opt} in
    e )
      # process option e
      exon="yes"
      ;;
    i)
      # option i takes input file path as argument
      GFFIN=$OPTARG
      ;;
    :)
      # capture the case where i was used without an argument
      echo "The $OPTARG option requires a file path as an argument" 1>&2
      exit 1
      ;;
    h )
      cat <<End-of-message
-------------------------------------
Convert a gff file generated by PROKKA to a gtf2bed-compatible gtf

Example usage:
gff2gtf_prokka.sh -e -i <inputGFFfile.gff>

Output:
GTF file on stdout, logfile in the form YYYYMMDD_HHMMSS_gff2gtf.log in the execution folder

Options:
-e        : convert 'transcript' key to 'exon' ('transcript' is produced by gffread -T)
-i FILE   : path to input GFF file (required)
-h        : help

Author:
aangeloo@gmail.com
-------------------------------------
End-of-message

      exit 0
      ;;
    \? )
      usage 1>&2
      exit 1
      ;;
  esac
  no_args="false" # if arguments were entered, getopts enters the loop
done
shift $((OPTIND -1))
[[ $no_args == "true" ]] && { usage; exit 1; }

#GFFIN=$1
GFFBASE=$(basename $GFFIN .gff)
logfile="$(date +"%Y%m%d-%H%M%S")-gff2gtf.log"
# remove previous log files in exec directory
rm -f *gff2gtf.log

echo "working on ${GFFIN}" >> $logfile
echo "basename is ${GFFBASE}" >> $logfile

# add rRNA gene_biotype in GFF
tmpfile0=$(mktemp)
cat ${GFFIN} | grep "\trRNA\t" | sed 's/$/;gene_biotype=ribosomal RNA/' > ${tmpfile0}
echo " $(wc -l $tmpfile0 | awk '{print $1}') rRNA records found" >> $logfile

# add tRNA gene_biotype in GFF
tmpfile1=$(mktemp)
cat ${GFFIN} | grep "\ttRNA\t" | sed 's/$/;gene_biotype=tRNA/' > ${tmpfile1}
echo " $(wc -l $tmpfile1 | awk '{print $1}') tRNA records found" >> $logfile

# add CDS gene_biotype in GFF
tmpfile2=$(mktemp)
cat ${GFFIN} | grep "\tCDS\t" | sed 's/$/;gene_biotype=CDS/' > ${tmpfile2}
echo " $(wc -l $tmpfile2 | awk '{print $1}') CDS records found" >> $logfile

# actual conversion
# use gsed?, then sed -n '/exon/!p' could become gsed -n '/\texon\t/!p' and capture exon flanked by tabs
if [ "$exon" == "yes" ]; then
  cat ${tmpfile0} ${tmpfile1} ${tmpfile2} | gffread -F -T | gsed -n '/\texon\t/!p' | gsed 's/\ttranscript\t/\texon\t/'
  echo "Converting all non-exon keys to 'exon' " >> $logfile
  else
  cat ${tmpfile0} ${tmpfile1} ${tmpfile2} | gffread -F -T
  echo "The original keys in the GFF file were kept" >> $logfile
fi

echo "Writing output to stdout" >> $logfile
#echo "The new file has $(wc -l ${GFFBASE}.gtf | awk '{print $1}') lines" >> $logfile
rm -f ${tmpfile0}
rm -f ${tmpfile1}
rm -f ${tmpfile2}
echo "Cheers!" >> $logfile
