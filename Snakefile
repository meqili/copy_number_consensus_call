## Define the wildcards to use in the file names.
wildcard_constraints:
  caller = "cnvkit|cnvnator",
  dupdel = "dup|del",
  combined_caller = "cnvkit_cnvnator"

## Define the first rule of the Snakefile. This rule determines what the final file is and which steps to be taken.
rule all:
    input:
        "results/cnv_consensus.tsv",
        "results/cnv_neutral.bed",
        "results/cnv-consensus.seg.gz"


scratch_loc = config["scratch"] + '/'
#########################      FILTER STEP FOR THE 2 CALL METHODS ####################################


rule cnvnator_filter:
    input:
        ## Define the location of the input file and take the extension from the config file
        events= scratch_loc + "cnvnator_cnvnator/{sample}" + str(config["cnvnator_ext"])
    output:
        ## Define the output files' names
        cnvnator_del= scratch_loc + "interim/{sample}.cnvnator.del.bed",
        cnvnator_dup= scratch_loc + "interim/{sample}.cnvnator.dup.bed"
    params:
        ## Take parameters from the config file and assign them into params for convinient use in the Shell section
        SIZE_CUTOFF=str(config["size_cutoff"]),
    shell:
        ## The awk command line is to filter out the raw file.
        ## The end result has 8 columns
        ## | chr# | start | end | CNV_length | copy_numbers | pval | seg.mean | CNV type |
        ## The first awk looks at column 1 `CNV type` to filter out for loss/gain.
        ## Then it prints out all of the 8 columns above
        ## cnvnator does not have columns for copy_numbers, pval and seg.mean. Set NA here
        ## The second awk filters the CNV length
        ## The sort command sorts the first digit of chromosome number numerically
        ## The last pipe is to introduce tab into the file and output file name.
        """awk '$1~/deletion/ {{print $10,$11,$12,$3,"NA","NA","NA","DEL"}}' {input.events} """
        """ | awk '{{if ($4 > {params.SIZE_CUTOFF}){{print}}}}' """
        """ | sort -k1,1 -k2,2n """
        """ | tr [:blank:] '\t' > {output.cnvnator_del} && """
        """awk '$1~/duplication/ {{print $10,$11,$12,$3,"NA","NA","NA","DUP"}}' {input.events} """
        """ | awk '{{if ($4 > {params.SIZE_CUTOFF}){{print}}}}' """
        """ | sort -k1,1 -k2,2n """
        """ | tr [:blank:] '\t' > {output.cnvnator_dup}"""

rule cnvkit_filter:
    input:
        ## Define the location of the input file and take the extension from the config file
        events= scratch_loc + "cnvkit_cnvkit/{sample}" + str(config["cnvkit_ext"])
    output:
        ## Define the output files' names
        cnvkit_del= scratch_loc + "interim/{sample}.cnvkit.del.bed",
        cnvkit_dup= scratch_loc + "interim/{sample}.cnvkit.dup.bed"
    params:
        ## Take parameters from the config file and assign them into params for convinient use in the Shell section
        SIZE_CUTOFF=str(config["size_cutoff"]),
    shell:
        ## The awk command line is to filter out the raw file.
        ## The end result has 8 columns
        ## | chr# | start | end | CNV_length | copy_numbers | pval | seg.mean | CNV type |
        ## The first awk filter out for loss/gain using column 7 ( < 2 == loss, > 2 == gain).
        ## It writes NA for p-value since the CNVkit results don't have p-vals. p_ttest?
        ## Then it prints out all 8 of the columns above.
        ## The second awk filters the CNV length, and add in the CNV type
        ## The sort command sorts the first digit of chromosome number numerically
        ## The last pipe is to introduce tab into the file and output file name.
        """awk '$7<2 {{print $2,$3,$4,($4-$3 + 1),$7,"NA",$6,"DEL"}}' {input.events} """
        """ | awk '{{if ($4 > {params.SIZE_CUTOFF}){{print}}}}' """
        """ | sort -k1,1 -k2,2n """
        """ | tr [:blank:] '\t' > {output.cnvkit_del} && """
        """awk '$7>2 {{print $2,$3,$4,($4-$3 + 1),$7,"NA",$6,"DUP"}}' {input.events} """
        """ | awk '{{if ($4 > {params.SIZE_CUTOFF}){{print}}}}' """
        """ | sort -k1,1 -k2,2n """
        """ | tr [:blank:] '\t' > {output.cnvkit_dup}"""

rule generate_excluded:
    # Combine the sets of regions that are not well called by CNV algorithms for exclusion
    input:
        "ref/telomeres.bed",
        "ref/centromeres.bed",
        "ref/heterochromatin.bed",
        "ref/immunoglobulin_regions.bed",
        "ref/segmental_dups.bed"
    output:
        "ref/cnv_excluded_regions.bed"
    shell:
        "cat {input} | cut -f 1-3 | sort -k1,1 -k2,2n | bedtools merge > {output}"

rule generate_callable:
    # Invert the excluded regions to generate a file of regions potentially called.
    # First filters out small regions <200Kb
    input:
        bed="ref/cnv_excluded_regions.bed",
        genome="ref/hg38.chrom.sizes"
    output:
        "ref/cnv_callable.bed"
    params:
        min_size = 200000
    shell:
        "awk '($3-$2) >= {params.min_size}' {input.bed}  "
        "| bedtools complement -i stdin -g {input.genome} "
        # remove alt chromosomes and mitochondria
        "| grep -v '_' "
        "| grep -v 'chrM' > {output}"


rule filter_excluded:
    input:
        ## Define the location of the input file and take the path/extension from the config file
        exclude_list="ref/cnv_excluded_regions.bed",
        bedfile= scratch_loc + "interim/{sample}.{caller}.{dupdel}.bed"
    output:
        ## Define the output files' names
        filtered_bed= scratch_loc + "interim/{sample}.{caller}.{dupdel}.filtered.bed"
    threads: 1
    shell:
        ## Invoke the bedtools subtract pass in the reference and CNVs files. Direct the stdout to a new file.
        "bedtools subtract -N -a {input.bedfile} -b {input.exclude_list} -f 0.5 > {output.filtered_bed}"


rule first_merge:
    input:
        ## Define the location of the input file and take the path/extension from the config file
        filtered_bed= scratch_loc + "interim/{sample}.{caller}.{dupdel}.filtered.bed"
    output:
        ## Define the output files' names
        merged_bed= scratch_loc + "interim/{sample}.{caller}.{dupdel}.filtered2.bed"
    threads: 1
    shell:
        ## Call on bedtools to merge any overlapping segment. Merging done for any segments within a single file.
        ## We considers any segments within 10,000 bp to be the same CNV.
        ## Merge but retain info from columns 2 (start pos), 3(end pos), 5(copy numbers), 7(seg.mean), 8(CNV type)
        "sort -k1,1 -k2,2n {input.filtered_bed}"
        "| bedtools merge -i stdin -d 10000"
        " -c 2,3,5,7,8 -o collapse,collapse,collapse,collapse,distinct"
        " > {output.merged_bed}"


rule restructure_column:
    input:
        ## Define the location of the input file and take the path/extension from the config file
        script=os.path.join(config["scripts"], "restructure_column.py"),
        merged_bed= scratch_loc + "interim/{sample}.{caller}.{dupdel}.filtered2.bed"
    output:
        ## Define the output files' names
        restructured_bed= scratch_loc + "interim/{sample}.{caller}.{dupdel}.filtered3.bed"
    threads: 1
    shell:
        "python3 {input.script} --file {input.merged_bed} > {output.restructured_bed}"


rule compare_cnv_methods:
    input:
        ## Define the location of the input file and take the path/extension from the config file
        script=os.path.join(config["scripts"], "compare_variant_calling_updated.py"),
        cnvkit= scratch_loc + "interim/{sample}.cnvkit.{dupdel}.filtered3.bed",
        cnvnator= scratch_loc + "interim/{sample}.cnvnator.{dupdel}.filtered3.bed"
    output:
        ## Define the output files' names
        cnvkit_cnvnator= scratch_loc + "interim/{sample}.cnvkit_cnvnator.{dupdel}.bed"
    threads: 1
    params:
        sample_name="{sample}"
    shell:
        "python3 {input.script} --cnvkit {input.cnvkit} --cnvnator {input.cnvnator} "
        "--cnvkit_cnvnator {output.cnvkit_cnvnator} --sample {params.sample_name}"


rule combine_merge_paired_cnv:
    input:
        ## Define the location of the input file
        cnvkit_cnvnator= scratch_loc + "interim/{sample}.cnvkit_cnvnator.{dupdel}.bed"
    output:
        ## Define the output files' names
        merged= scratch_loc + "interim/{sample}.{dupdel}.merged.bed"
    threads: 1
    shell:
        ## Combine the input file, sort and output to one file
        ## Columns 4 and 5 hold the original CNV calls from CNVkit and cnvnator, respectively.
        ## We want to retain info in these columns when merging these files so we use COLLAPSE to keep the information in these columns
        ## Columns 6 and 7 are the CNVtype (DEL, DUP) and Sample_name, respectively.
        ## AT THIS POINT, these columns of the input files hold the same values, thus we perform DISTINCT, which is to take the unique of columns 6 and 7.
        ## As for column 8, this column holds the files that were merged to get a specific CNV. We want to keep all information here so we COLLAPSE it.
        "sort -k1,1 -k2,2n {input.cnvkit_cnvnator} "
        "| bedtools merge -c 4,5,6,7,8 -o collapse,collapse,distinct,distinct,collapse "
        "> {output.merged}"

rule remove_inset_calls:
    ## Sometimes calls are inset within one another: one del call within the range of a dup call, or vice versa.
    ## To fix this, we will use bedtools to subtract del calls from dup calls, which splits the dup into two (or more)
    ## segments and removes the overlap.
    ## This subtraction will remove any dup segments that lay entirely within a del segment, so those need to be added back.
    ## We do this by finding the intersection of all dup and del segments, which includes regions where both are present,
    ## but may remove the annotation of which original segment was 'fully enclosed' by a segment of the opposite call.
    ## To restore that inforamtion we intersect the original dup calls with those intersection calls,
    ## requiring full reciprocal coverage (-r 1) to find only those dup calls that are in the original set and NOT enclosed by a del call
    ##
    ## The entire process is also repeated with the opposite order, to caputure all del calls, then the results are merged
    ## separately for dups and dels.
    input:
        dup_merge =  scratch_loc + "interim/{sample}.dup.merged.bed",
        del_merge =  scratch_loc + "interim/{sample}.del.merged.bed"
    output:
        dup_merge =  scratch_loc + "endpoints/{sample}.dup.merged.final.bed",
        del_merge =  scratch_loc + "endpoints/{sample}.del.merged.final.bed",
        dupdel_diff = scratch_loc + "interim/{sample}.dup-del.bed",
        deldup_diff = scratch_loc + "interim/{sample}.del-dup.bed",
        deldup_intersect = scratch_loc + "interim/{sample}.deldup_intersect.bed",
        del_intersect = scratch_loc + "interim/{sample}.del_intersect.bed",
        dup_intersect = scratch_loc + "interim/{sample}.dup_intersect.bed"
    shell:
        # subtract deletion segments from duplications (and vice versa)
        "bedtools subtract -a {input.dup_merge} -b {input.del_merge}"
        " > {output.dupdel_diff} &&"
        "bedtools subtract -a {input.del_merge} -b {input.dup_merge}"
        " > {output.deldup_diff} &&"
        # intersect dups and dels to find regions where both where present
        "bedtools intersect -a {input.dup_merge} -b {input.del_merge}"
        " > {output.deldup_intersect} &&"
        # find which of the intersection regions came from a duplication segment, then which came from deletions
        "bedtools intersect -f 1 -r -a {input.dup_merge} -b {output.deldup_intersect}"
        " >  {output.dup_intersect} &&"
        "bedtools intersect -f 1 -r -a {input.del_merge} -b {output.deldup_intersect}"
        " >  {output.del_intersect} &&"
        # combine dups and dels separately
        "cat {output.dupdel_diff} {output.dup_intersect}"
        " > {output.dup_merge} &&"
        "cat {output.deldup_diff} {output.del_intersect}"
        " > {output.del_merge}"

rule neutral_regions:
    ## for each sample, find the segments not called as either dups or dels with bedtools
    ## then append the sample name
    input:
        dup_merge =  scratch_loc + "endpoints/{sample}.dup.merged.final.bed",
        del_merge =  scratch_loc + "endpoints/{sample}.del.merged.final.bed",
        called = "ref/cnv_callable.bed"
    output:
         scratch_loc + "endpoints/{sample}.neutral.bed"
    shell:
        "bedtools subtract -a {input.called} -b {input.dup_merge}"
        " | bedtools subtract -a stdin -b {input.del_merge}"
        " | sed 's/$/\t{wildcards.sample}/' > {output}"

rule merge_neutral:
    input:
        expand(scratch_loc + "endpoints/{sample}.neutral.bed",
               sample = config["samples"])
    output:
        "results/cnv_neutral.bed"
    shell:
        "cat {input} > {output}"


rule merge_all:
    input:
        ## Take all of the del and dup files of ALL samples as input.
        expand(scratch_loc + "endpoints/{sample}.{dupdel}.merged.final.bed",
               sample = config["samples"],
               dupdel = ["dup", "del"] )
    output:
        scratch_loc + "endpoints/all_CNVs_combined.tsv"
    run:
        ## Add a header and combine all of the files.
        shell("echo -e 'chrom\tstart\tend\tcnvkit_CNVs\tcnvnator_CNVs\tCNV_type\tBiospecimen' > {output}")
        for file in input:
            shell("cut -f 1-7 {file} >> {output}")


rule clean_output:
    input:
        script=os.path.join(config["scripts"], "remove_dup_NULL_overlap_entries.py"),
        cnv_file = scratch_loc + "endpoints/all_CNVs_combined.tsv"
    output:
        "results/cnv_consensus.tsv"
    shell:
        "python3 {input.script} --file {input.cnv_file} > {output}"

rule make_segfile:
    input:
        script= os.path.join(config["scripts"], "bed_to_segfile.R"),
        consensus = "results/cnv_consensus.tsv",
        neutral = "results/cnv_neutral.bed",
        uncalled = "results/uncalled_samples.tsv"
    output:
        "results/cnv-consensus.seg.gz"
    shell:
        "Rscript {input.script}"
        " -i {input.consensus}"
        " -n {input.neutral}"
        " -u {input.uncalled}"
        " -o {output}"
