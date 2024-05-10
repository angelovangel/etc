#! /usr/bin/env bash

# bin reads in a fastq file to one fastq file per bin.
# based on the output of lrbinner, where every line corresponds to the respective read bin
# https://github.com/anuradhawick/LRBinner


start=1
end=4
while read bin; do 
    #seqkit range -r $counter:$counter $2 >> bin-$line.fastq
    #echo $counter $line
    sed -n "$start, $end p; $end q" $2 >> bin-$bin.fastq
    #head -n $end $2 | tail -n 4 >> bin-$bin.fastq
    start=$(($start + 4))
    end=$(($end + 4))
done < $1

# get line numbers of a particular bin
#grep -n "0" $1 | cut -d: -f1

# get records by address

#grep -n "1,+3p;4+3p" $2