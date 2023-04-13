## prepossess cnvkit outputs
import pandas as pd
cns_file="/Users/liq3/CNV-SV-analyses/kfdrc-cnvkit-BS_6M8T4W39/786e1a92-efb5-42ec-ac50-6a08620a5319.call.ballele_call.cns"
seg_file="/Users/liq3/CNV-SV-analyses/kfdrc-cnvkit-BS_6M8T4W39/786e1a92-efb5-42ec-ac50-6a08620a5319.call.ballele_call.seg"
cns_df = pd.read_csv(cns_file, delimiter="\t", dtype=str)
seg_df = pd.read_csv(seg_file, delimiter="\t", dtype=str)

merged_df = seg_df.join(cns_df[['cn','p_ttest']])
with open(cns_file + ".seg", "w") as file_out:
    merged_df.to_csv(file_out, sep="\t", index=False)