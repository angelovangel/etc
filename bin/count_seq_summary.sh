#! /usr/bin/env ksh

# pass a ONT sequencing summary file and return bases and reads (pass only)
# use ksh to be able to return SI units automagically

# get col index as they are not very consistent
pass=$(head -1 ${1} | sed 's/\t/\n/g' | nl | grep 'passes_filtering' | cut -f 1)
len=$(head -1 ${1} | sed 's/\t/\n/g' | nl | grep 'sequence_length_template' | cut -f 1)
# 

# bases \t reads
z=$(awk -v a="$pass" -v b="$len" '$a ~ /TRUE/ {sum+=$b; count++} END {printf "x=%s \n y=%s", sum, count}' "${1}")
#bases=$(awk '$12 ~ /TRUE/ {sum+=$16} END {printf "%s", sum}' "${1}")
#reads=$(awk '$12 ~ /TRUE/ {count++} END {printf "%s", count}' "${1}")

# the above assigns bases and reads in awk and assigns to z, when z is evaluated x and y become shell variables
# this way only one pass is needed 
# https://www.theunixschool.com/2012/08/awk-passing-awk-variables-to-shell.html
eval $z
file=$(basename ${1})
#printf "file,reads,bases\n"
printf "$file,%#d,%#d\n" $x $y
