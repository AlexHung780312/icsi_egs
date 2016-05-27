#!/bin/bash

if [ $# -ne 2 ]; then
  echo "local/icsi_data_prep.sh LDC2004S02_PATH LDC2004T04_PATH"
  exit 1
fi

sdir=$1
tdir=$2
dir=`pwd`/data/local/data
lmdir=`pwd`/data/local/nist_lm
mkdir -p $dir $lmdir
local=`pwd`/local
utils=`pwd`/utils

. ./path.sh # Needed for KALDI_ROOT
sph2pipe=$KALDI_ROOT/tools/sph2pipe_v2.5/sph2pipe
if [ ! -x $sph2pipe ]; then
  echo "Could not find (or execute) the sph2pipe program at $sph2pipe";
  exit 1;
fi

# mrt 2 stm like
if [ ! -f $dir/all.txt ]; then
  for f in $tdir/icsi_mr_transcr/transcripts/B*.mrt; do
    local/mrt_tag.py -r $f | \
      local/mrt2list.pl - | \
      awk '{if ($3!="far"){print $n}}' >> $dir/all.txt;
  done
fi
wc $dir/all.txt
# text
[ ! -f $dir/all.txt ] && exit 1
awk 'BEGIN{FS="\t"}{printf("%s_%s_%06d ", $2, $1, NR); $1=$2=$3=$4=$5=""; print $6;}' $dir/all.txt > $dir/text
# spk
awk 'BEGIN{FS="\t"}{printf("%s_%s_%06d %s\n", $2, $1, NR, $2);}' $dir/all.txt > $dir/utt2spk
# wav
awk -v sdir="$sdir" 'BEGIN{FS="\t"}{printf("%s_%s_%06d sph2pipe -f wav -t %.3f:%.3f %s/speech/%s/%s.sph |\n", $2, $1, NR, $4, $5, sdir, $1, $3);}' $dir/all.txt > $dir/wav.scp
#
mkdir -p `pwd`/data/all
target=`pwd`/data/all
sort $dir/text | local/text_normalize.py > $target/text
sort $dir/utt2spk > $target/utt2spk
./utils/utt2spk_to_spk2utt.pl $dir/utt2spk | sort > $target/spk2utt
sort $dir/wav.scp > $target/wav.scp

./utils/validate_data_dir.sh --no-feats data/all
