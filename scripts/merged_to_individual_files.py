## Qi Li
## 2023


# Imports in the pep8 order https://www.python.org/dev/peps/pep-0008/#imports
# Standard library
import argparse
import os

# Related third party
import numpy as np
import pandas as pd

## Define the callers and the extension to give the intermediate files
extensions = {"cnvkit": ".cnvkit", "cnvnator": ".cnvnator"}


parser = argparse.ArgumentParser(
    description="""This script prints a snakemake config file
                                                to the specified filename."""
)
parser.add_argument("--sample", required=True, help="provide sample ID")
parser.add_argument("--cnvnator", required=True, help="path to the cnvnator file")
parser.add_argument("--cnvkit", required=True, help="path to the cnvkit file")
parser.add_argument("--snake", required=True, help="path for snakemake config file")
parser.add_argument("--scratch", required=True, help="directory for scratch files")
parser.add_argument(
    "--uncalled",
    required=True,
    help="path for the table of sample-caller outputs removed and not called for too many CNVs",
)
parser.add_argument(
    "--maxcnvs", default=2500, help="samples with more than 2500 cnvs are set to blank"
)
parser.add_argument("--cnvsize", default=3000, help="cnv cutoff size in base pairs")


args = parser.parse_args()
sample = args.sample
scratch_d = args.scratch


# Read data files and get sample counts
caller_dfs = {}
samples = {}
out_dirs = {}
chromosome_list = ['chr' + str(chrom) for chrom in list(range(1,22))+ ["X", "Y"]]
for caller in extensions.keys():
    # use vars() to access args Namespace as dictionary
    my_file = vars(args)[caller]
    if caller == "cnvnator":
        my_df = pd.read_csv(my_file, delimiter="\t", dtype=str, header=None) # CNVnator result use header=None
        my_df.columns = ["CNV type", "chr:start-end", "CNV_length", "Normalized RD", "e-val_by_t-test",
                         "e-val_by_Gaussian_tail", "e-val_by_t-test_(middle)",
                         "e-val_by_Gaussian_tail_(middle)", "Fraction_of_reads_with_0_mapping_quality"]
        my_df = my_df.join(my_df["chr:start-end"].str.split(':|-',expand=True).add_prefix('loc_'))
        my_df = my_df[my_df['loc_0'].isin(chromosome_list)]
    else:
        my_df = pd.read_csv(my_file, delimiter="\t", dtype=str)
        my_df = my_df[my_df['chrom'].isin(chromosome_list)]
    ## Define and create assumed directories
    my_dn = "_".join([caller, caller])  
    my_dir = os.path.join(scratch_d, my_dn)
    if not os.path.exists(my_dir):
        os.makedirs(my_dir)
    caller_dfs[caller] = my_df
    out_dirs[caller] = my_dir


bad_calls = []

## Loop through each sample, search for that sample in each of the three dataframes,
## and create a file of the sample in each directory
for caller in extensions.keys():
    # get caller specific variables
    my_ext = extensions[caller]
    my_df = caller_dfs[caller]
    # my_id = id_headers[caller]
    my_dir = out_dirs[caller]

    ## Write cnvs to file if less than maxcnvs / otherwise empty file and add to bad_calls list
    with open(os.path.join(my_dir, sample + my_ext), "w") as file_out:
        if my_df.shape[0] <= args.maxcnvs and my_df.shape[0] > 0:
            my_df.to_csv(file_out, sep="\t", index=False)
        else:
            bad_calls.append(sample + "\t" + caller + "\n")


## Make the Snakemake config file. Write all of the sample names into the config file
with open(args.snake, "w") as file:
    file.write("samples:" + "\n")
    file.write("  " + str(sample) + ":" + "\n")

    ## Define the extension for the config file
    for caller in extensions.keys():
        file.write(caller + "_ext: " + extensions[caller] + "\n")

    ## Define location for python scripts and scratch
    file.write("scripts: " + os.path.dirname(os.path.realpath(__file__)) + "\n")
    file.write("scratch: " + scratch_d + "\n")

    ## Define the size cutoff and freec's pval cut off.
    file.write("size_cutoff: " + str(args.cnvsize) + "\n")

## Write out the bad calls file
bad_calls.sort()
with open(args.uncalled, "w") as file:
    file.write("sample\tcaller\n")
    file.writelines(bad_calls)