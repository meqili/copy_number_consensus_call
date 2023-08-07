## download CNVkit output files ##
desti_file="70027d29-780b-4629-93ea-444f3c798603.call.ballele_call.cns"
taskID=`echo $desti_file | cut -d '.' -f1`
fileID_pre=`sudo sb files list --project d3b-bixu-ops/sd-s9agk8xv-alignment-wgs-normal | grep $desti_file | cut -c2-6`
sudo sb files list --project d3b-bixu-ops/sd-s9agk8xv-alignment-wgs-normal | grep \'$taskID | grep $fileID_pre | awk -F "'" '{print "sudo sb download --file " $2}'

## download CNVnator output files ##
desti_file="77828173-da29-4af7-8171-733a640792dc.cnvnator_call.txt"
taskID=`echo $desti_file | cut -d '.' -f1`
fileID_pre=`sudo sb files list --project d3b-bixu-ops/sd-s9agk8xv-alignment-wgs-normal | grep $desti_file | cut -c2-6`
sudo sb files list --project d3b-bixu-ops/sd-s9agk8xv-alignment-wgs-normal | grep \'$taskID | grep $fileID_pre | awk -F "'" '{print "sudo sb download --file " $2}'


sample="BS_5R51C6RG"
CNVkit_segfile=`ls kfdrc-cnvkit-$sample/*.call.ballele_call.seg`
CNVkit_cnsfile=`ls kfdrc-cnvkit-$sample/*.call.ballele_call.cns`
CNVkit_callfile=$CNVkit_cnsfile".seg"
CNVnator_callfile=`ls kfdrc-cnvnator-"$sample"/*.cnvnator_call.txt`
## 
paste $CNVkit_segfile <(cut -f 6 -f 8 $CNVkit_cnsfile)  > $CNVkit_callfile
for chrom in {1..22} X Y; do
    chromosome="chr"$chrom
    awk -v CHR="$chromosome" '$2==CHR {print $0}' $CNVkit_callfile
done | wl
for chrom in {1..22} X Y; do
    chromosome="chr"$chrom":"
    awk -v CHR="$chromosome" '$2~CHR {print $0}' $CNVnator_callfile
done | wl

# for sample in BS_5R51C6RG BS_6M8T4W39 BS_88GCNYAD BS_F5Z5VJF7 BS_JDBS748M BS_V6CNFCGS