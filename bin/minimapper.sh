#!/usr/bin/env bash

# run minimap on ONT data, sort and index bam files

usage()
{
    echo "Usage: minimapper [options] <target.fa> <query.fastq>"
    exit 2
}
# options
# -p number of processors to use
# -d use dorado aligner instead of minimap2

# output is sample.bam (sorted bam, if sample.fastq was input)

# set default
processors=4

while getopts ":p:d" c; do
  case ${c} in
    p )
      processors=$OPTARG
      ;;
    d )
      dorado=true
      ;;
    \? )
      echo "Invalid option: $OPTARG" 1>&2
      usage
      ;;
    : )
      echo "Invalid option: $OPTARG requires an argument" 1>&2
      usage
      ;;
  esac
done
shift $((OPTIND -1))


#strip=${2%.*}
samplename=$(basename $2 | cut -d. -f1) # this seems to be the only secure way for now to get basename with no extensions
echo $samplename
#echo $processors
#exit 2 

if [ "$dorado" = true ]; then
    dorado aligner -t $processors --mm2-opts "-x lr:hq" $1 $2 | \
    samtools sort -@ $processors -o $samplename.align.bam - 
    samtools index -@ $processors $samplename.align.bam
    echo "Dorado alignment complete. Output: $samplename.align.bam"
    exit 0
else
    minimap2 -t $processors -ax lr:hq --secondary=no --eqx $1 $2 > $samplename.align.sam
fi

SAMFILE=$samplename.align.sam
if [ -f "$SAMFILE" ]; then
    echo "$SAMFILE exists and will be used to make a sorted and indexed bam..."
    
    samtools view -S -b -@ $processors -T $1 $SAMFILE | \
    samtools sort -@ $processors -o $samplename.align.bam -
    samtools index -@ $processors $samplename.align.bam

    rm $SAMFILE
    echo "Minimap2 alignment complete. Output: $samplename.align.bam"
else 
    echo "$SAMFILE does not exist."
    exit 2
fi
