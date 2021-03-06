#!/bin/bash

# Copyright 2016  Alex Hung
#           2013  Arnab Ghoshal, Pawel Swietojanski

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
# WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
# MERCHANTABLITY OR NON-INFRINGEMENT.
# See the Apache 2 License for the specific language governing permissions and
# limitations under the License.

# To be run from one directory above this script.

# Begin configuration section.
fisher=
order=3
swbd=
google=
web_sw=
web_fsh=
web_mtg=
# end configuration sections

help_message="Usage: "`basename $0`" [options] <train-txt> <dev-txt> <dict> <out-dir>
Train language models for ICSI and optionally for Switchboard, Fisher and web-data from University of Washington.\n
options:
  --help          # print this message and exit
  --fisher DIR    # directory for Fisher transcripts
  --order N       # N-gram order (default: '$order')
  --swbd DIR      # Directory for Switchboard transcripts
  --web-sw FILE   # University of Washington (191M) Switchboard web data
  --web-fsh FILE  # University of Washington (525M) Fisher web data
  --web-mtg FILE  # University of Washington (150M) CMU+ICSI+NIST meeting data
";

. utils/parse_options.sh

if [ $# -ne 4 ]; then
  printf "$help_message\n";
  exit 1;
fi

train=$1    # data/ihm/train/text
dev=$2      # data/ihm/dev/text
lexicon=$3  # data/ihm/dict/lexicon.txt
dir=$4      # data/local/lm

for f in "$text" "$lexicon"; do
  [ ! -f $x ] && echo "$0: No such file $f" && exit 1;
done

set -o errexit
mkdir -p $dir
export LC_ALL=C

cut -d' ' -f6- $train | gzip -c > $dir/train.gz
cut -d' ' -f6- $dev | gzip -c > $dir/dev.gz

awk '{print $1}' $lexicon | sort -u > $dir/wordlist.lex
gunzip -c $dir/train.gz | tr ' ' '\n' | grep -v ^$ | sort -u > $dir/wordlist.train
sort -u $dir/wordlist.lex $dir/wordlist.train > $dir/wordlist

ngram-count -maxent -maxent-convert-to-arpa -text $dir/train.gz -order $order -prune 1e-7 \
  -lm $dir/icsi.o${order}g.kn.gz
echo "PPL for ICSI LM:"
ngram -unk -lm $dir/icsi.o${order}g.kn.gz -ppl $dir/dev.gz
ngram -unk -lm $dir/icsi.o${order}g.kn.gz -ppl $dir/dev.gz -debug 2 >& $dir/ppl2
mix_ppl="$dir/ppl2"
mix_tag="icsi"
mix_lms=( "$dir/icsi.o${order}g.kn.gz" )
num_lms=1

if [ ! -z "$swbd" ]; then
  mkdir -p $dir/swbd

  find $swbd -iname '*-trans.text' -exec cat {} \; | cut -d' ' -f4- \
    | gzip -c > $dir/swbd/text0.gz
  gunzip -c $dir/swbd/text0.gz | swbd_map_words.pl | gzip -c \
    > $dir/swbd/text1.gz
  ngram-count -text $dir/swbd/text1.gz -order $order -limit-vocab \
    -vocab $dir/wordlist -unk -map-unk "<unk>" -kndiscount -interpolate \
    -lm $dir/swbd/swbd.o${order}g.kn.gz
  echo "PPL for SWBD LM:"
  ngram -unk -lm $dir/swbd/swbd.o${order}g.kn.gz -ppl $dir/dev.gz
  ngram -unk -lm $dir/swbd/swbd.o${order}g.kn.gz -ppl $dir/dev.gz -debug 2 \
    >& $dir/swbd/ppl2

  mix_ppl="$mix_ppl $dir/swbd/ppl2"
  mix_tag="${mix_tag}_swbd"
  mix_lms=("${mix_lms[@]}" "$dir/swbd/swbd.o${order}g.kn.gz")
  num_lms=$[ num_lms + 1 ]
fi

if [ ! -z "$fisher" ]; then
  [ ! -d "$fisher/data/trans" ] \
    && echo "Cannot find transcripts in Fisher directory: '$fisher'" \
    && exit 1;
  mkdir -p $dir/fisher

  find $fisher -follow -path '*/trans/*fe*.txt' -exec cat {} \; | grep -v ^# | grep -v ^$ \
    | cut -d' ' -f4- | gzip -c > $dir/fisher/text0.gz
  gunzip -c $dir/fisher/text0.gz | local/fisher_map_words.pl \
    | gzip -c > $dir/fisher/text1.gz
  ngram-count -debug 0 -text $dir/fisher/text1.gz -order $order -limit-vocab \
    -vocab $dir/wordlist -unk -map-unk "<unk>" -kndiscount -interpolate \
    -lm $dir/fisher/fisher.o${order}g.kn.gz
  echo "PPL for Fisher LM:"
  ngram -unk -lm $dir/fisher/fisher.o${order}g.kn.gz -ppl $dir/dev.gz
  ngram -unk -lm $dir/fisher/fisher.o${order}g.kn.gz -ppl $dir/dev.gz -debug 2 \
   >& $dir/fisher/ppl2

  mix_ppl="$mix_ppl $dir/fisher/ppl2"
  mix_tag="${mix_tag}_fsh"
  mix_lms=("${mix_lms[@]}" "$dir/fisher/fisher.o${order}g.kn.gz")
  num_lms=$[ num_lms + 1 ]
fi

if [ ! -z "$google1B" ]; then
  mkdir -p $dir/google
  wget -O $dir/google/cantab.lm3.bz2 http://vm.cantabresearch.com:6080/demo/cantab.lm3.bz2
  wget -O $dir/google/150000.lex http://vm.cantabresearch.com:6080/demo/150000.lex

  ngram -unk -limit-vocab -vocab $dir/wordlist -lm $dir/google.cantab.lm3.bz3 \
     -write-lm $dir/google/google.o${order}g.kn.gz

  mix_ppl="$mix_ppl $dir/goog1e/ppl2"
  mix_tag="${mix_tag}_fsh"
  mix_lms=("${mix_lms[@]}" "$dir/google/google.o${order}g.kn.gz")
  num_lms=$[ num_lms + 1 ]
fi

## The University of Washington conversational web data can be obtained as:
## wget --no-check-certificate http://ssli.ee.washington.edu/data/191M_conversational_web-filt+periods.gz
if [ ! -z "$web_sw" ]; then
  [ ! -d $dir/web_conv ] && mkdir -p $dir/web_conv
  echo $web_sw
  if [ ! -f $dir/web_conv/web_conv.gz ]; then
    gunzip -c $web_sw | grep -v '#' | tr '[:lower:]' '[:upper:]' | \
      gzip -c > $dir/web_conv/web_conv.gz
  fi
  ngram-count -text $dir/web_conv/web_conv.gz -order $order -prune 1e-14 \
    -kndiscount -interpolate \
    -lm $dir/web_conv/web_conv.o${order}g.kn.gz
  echo "PPL for WebConversational LM:"
  ngram -unk -lm $dir/web_conv/web_conv.o${order}g.kn.gz -ppl $dir/dev.gz
  ngram -unk -lm $dir/web_conv/web_conv.o${order}g.kn.gz -ppl $dir/dev.gz -debug 2 \
   >& $dir/web_conv/ppl2

  mix_ppl="$mix_ppl $dir/web_conv/ppl2"
  mix_tag="${mix_tag}_conv"
  mix_lms=("${mix_lms[@]}" "$dir/web_conv/web_conv.o${order}g.kn.gz")
  num_lms=$[ num_lms + 1 ]

fi

## The University of Washington Fisher conversational web data can be obtained as:
## wget --no-check-certificate http://ssli.ee.washington.edu/data/525M_fisher_conv_web-filt+periods.gz
if [ ! -z "$web_fsh" ]; then
  [ ! -d $dir/web_fsh ] && mkdir -p $dir/web_fsh
  echo $web_fsh
  if [ ! -f $dir/web_fsh/web_fsh.gz ]; then
    gunzip -c $web_fsh | grep -v '#' |  local/fisher_map_words.pl | tr '[:lower:]' '[:upper:]' | \
      gzip -c > $dir/web_fsh/web_fsh.gz
  fi
  ngram-count -text $dir/web_fsh/web_fsh.gz -order $order -prune 1e-14 \
    -kndiscount -interpolate \
    -lm $dir/web_fsh/web_fsh.o${order}g.kn.gz
  echo "PPL for WebFisher LM:"
  ngram -unk -lm $dir/web_fsh/web_fsh.o${order}g.kn.gz -ppl $dir/dev.gz
  ngram -unk -lm $dir/web_fsh/web_fsh.o${order}g.kn.gz -ppl $dir/dev.gz -debug 2 \
   >& $dir/web_fsh/ppl2

  mix_ppl="$mix_ppl $dir/web_fsh/ppl2"
  mix_tag="${mix_tag}_fsh"
  mix_lms=("${mix_lms[@]}" "$dir/web_fsh/web_fsh.o${order}g.kn.gz")
  num_lms=$[ num_lms + 1 ]

fi

## The University of Washington meeting web data can be obtained as:
## wget --no-check-certificate http://ssli.ee.washington.edu/data/150M_cmu+icsi+nist-meetings.gz
if [ ! -z "$web_mtg" ]; then
  echo "Interpolating web-LM not implemented yet"
fi

if [ ! -z "$giga" ]; then
  [ ! -d $dir/giga ] && mkdir -p $dir/giga
  [ ! -f $dir/giga/lm_giga_64k_nvp_3gram.zip ] && wget -O $dir/giga/lm_giga_64k_nvp_3gram.zip  http://www.keithv.com/software/giga/lm_giga_64k_nvp_3gram.zip 
  unzip -d $dir/giga $dir/giga/lm_giga_64k_nvp_3gram.zip
  awk '{print $1 " " toupper($1)}' $dir/giga/lm_giga_64k_nvp_3gram/wlist_giga_64k_nvp > $dir/giga/lm_giga_64k_nvp_3gram/toupper.txt

fi
if [ $num_lms -gt 1  ]; then
  echo "Computing interpolation weights from: $mix_ppl"
  compute-best-mix $mix_ppl >& $dir/mix.log
  grep 'best lambda' $dir/mix.log \
    | perl -e '$_=<>; s/.*\(//; s/\).*//; @A = split; for $i (@A) {print "$i\n";}' \
    > $dir/mix.weights
  weights=( `cat $dir/mix.weights` )
  cmd="ngram -lm ${mix_lms[0]} -lambda ${weights[1]} -mix-lm ${mix_lms[1]}"
  for i in `seq 2 $((num_lms-1))`; do
    cmd="$cmd -mix-lm${i} ${mix_lms[$i]} -mix-lambda${i} ${weights[$i]}"
  done
  cmd="$cmd -unk -write-lm $dir/${mix_tag}.o${order}g.kn.gz"
  echo "Interpolating LMs with command: \"$cmd\""
  $cmd
  echo "PPL for the interolated LM:"
  ngram -unk -lm $dir/${mix_tag}.o${order}g.kn.gz -ppl $dir/dev.gz
fi

#save the lm name for furher use
echo "${mix_tag}.o${order}g.kn" > $dir/final_lm
