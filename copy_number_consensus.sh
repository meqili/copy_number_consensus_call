## The awk command line is to filter out the raw file.
## The end result has 9 columns
## | chr# | start | end | CNV_length | gene | copy_numbers | pval | seg.mean | CNV type |
## The first awk filter out for loss/gain using column copy_numbers ( < 2 == loss, > 2 == gain).
## Then it prints out all 9 of the columns above.
## The second awk filters the CNV length, and add in the CNV type
## The sort command sorts the first digit of chromosome number numerically
## The last pipe is to introduce tab into the file and output file name.

maxcnvs=2500 # samples with more than 2500 cnvs are set to blank
cnvsize=3000 # cnv cutoff size in base pairs

scratch_loc="/Users/liq3/CNV-SV-analyses/"
input_file="${scratch_loc}kfdrc-cnvkit-BS_6M8T4W39/786e1a92-efb5-42ec-ac50-6a08620a5319.call.ballele_call.cns"
sample=$(echo $(basename $(dirname $input_file)) | cut -d'-' -f3)
cnvkit_del="${scratch_loc}interim/${sample}.cnvkit.del.bed"
cnvkit_dup="${scratch_loc}interim/${sample}.cnvkit.dup.bed"
mkdir -p $(dirname $cnvkit_del)

awk '$6<2 {{print $1,$2,$3,($3-$2 + 1),$4,$6,$8,$6,"DEL"}}' ${input_file} \
 | awk -v SIZE_CUTOFF='$cnvsize' '{if ($4 > SIZE_CUTOFF){print}}' \
 | sort -k1,1 -k2,2n \
 | tr -s '\t' > $cnvkit_del && 
awk '$6<2 {{print $1,$2,$3,($3-$2 + 1),$4,$6,$8,$6,"DUP"}}' ${input_file} \
 | awk -v SIZE_CUTOFF='$cnvsize' '{if ($4 > SIZE_CUTOFF){print}}' \
 | sort -k1,1 -k2,2n \
 | tr -s '\t' > $cnvkit_dup

# Combine the sets of regions that are not well called by CNV algorithms for exclusion
# skipped this part as the output files is in github 
# location: /Users/liq3/CNV-SV-analyses/copy_number_consensus_call/ref/cnv_excluded_regions.bed

# Invert the excluded regions to generate a file of regions potentially called.
# First filters out small regions <200Kb
# output location: /Users/liq3/CNV-SV-analyses/copy_number_consensus_call/ref/cnv_callable.bed"
# removed alt chromosomes and mitochondria

######## filter_excluded #######
## Invoke the bedtools subtract pass in the reference and CNVs files. Direct the stdout to a new file.
exclude_list=“/Users/liq3/CNV-SV-analyses/copy_number_consensus_call/ref/cnv_excluded_regions.bed”
bedtools subtract -N -a ${bedfile} -b ${exclude_list} -f 0.5 > ${filtered_bed}