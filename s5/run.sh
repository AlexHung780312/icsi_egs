#!/bin/bash

. ./cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
           ## This relates to the queue.

# This is a shell script, but it's recommended that you run the commands one by
# one by copying and pasting into the shell.
stage=0
decode=false
icsi_sph=/usr/local/corpus/LDC2004S02
icsi_trs=/usr/local/corpus/LDC2004T04

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $stage -le 0 ]; then
local/icsi_data_prep.sh $icsi_sph $icsi_trs || exit 1;
tfile=`mktemp`
trap "rm -f $tfile" EXIT
./utils/shuffle_list.pl data/all/utt2spk > $tfile
mv $tfile data/all/utt2spk
./utils/subset_data_dir_tr_cv.sh data/all data/train data/dev || exit 1
utils/prepare_lang.sh data/local/dict "<unk>" data/local/lang data/lang || exit 1;
./local/icsi_train_lms.sh --order 3 --web-sw /usr/local/corpus/weblm/191M_conversational_web-filt+periods.gz --web-fsh /usr/local/corpus/weblm/525M_fisher_conv_web-filt+periods.gz data/train/text data/dev/text data/local/dict/lexicon.txt data/local/nist_lm/3g || exit 1
./local/icsi_train_lms.sh --order 4 --web-sw /usr/local/corpus/weblm/191M_conversational_web-filt+periods.gz --web-fsh /usr/local/corpus/weblm/525M_fisher_conv_web-filt+periods.gz data/train/text data/dev/text data/local/dict/lexicon.txt data/local/nist_lm/4g || exit 1
local/icsi_format_data.sh || exit 1;
fi

# Now make MFCC features.
# mfccdir should be some place with a largish disk where you
# want to store MFCC features.
mfccdir=mfcc
if [ $stage -le 1 ]; then
for x in train dev; do
  steps/make_mfcc.sh --cmd "$train_cmd" --nj 30 --compress false \
    data/$x exp/make_mfcc/$x $mfccdir || exit 1;
  steps/compute_cmvn_stats.sh data/$x exp/make_mfcc/$x $mfccdir || exit 1;
done
fi

# Note: the --boost-silence option should probably be omitted by default
# for normal setups.  It doesn't always help. [it's to discourage non-silence
# models from modeling silence.]
if [ $stage -le 2 ]; then
steps/train_mono.sh --boost-silence 1.25 --nj 10 --cmd "$train_cmd" \
  data/train data/lang exp/mono0a || exit 1;
fi

if [ $stage -le 3 ]; then
if $decode; then
$mkgraph_cmd exp/mono0a/log/mkgraph.log \
  utils/mkgraph.sh --mono data/lang_test \
   exp/mono0a exp/mono0a/graph
steps/decode_nolats.sh --nj 10 --cmd "$decode_cmd" exp/mono0a/graph \
  data/dev exp/mono0a/decode_dev
fi
fi

if [ $stage -le 4 ]; then
steps/align_si.sh --boost-silence 1.25 --nj 10 --cmd "$train_cmd" \
  data/train data/lang exp/mono0a exp/mono0a_ali || exit 1;
steps/train_deltas.sh --boost-silence 1.25 --cmd "$train_cmd" 1500 12000 \
  data/train data/lang exp/mono0a_ali exp/tri1 || exit 1;
fi

if [ $stage -le 5 ]; then
while [ ! -f data/lang_test/tmp/LG.fst ] || \
   [ -z data/lang_test/tmp/LG.fst ]; do
  sleep 20;
done
sleep 30;
# or the mono mkgraph.sh might be writing
# data/lang_test_tgpr/tmp/LG.fst which will cause this to fail.
fi

if [ $stage -le 6 ]; then
if $decode; then
$mkgraph_cmd exp/tri1/log/mkgraph.log \
  utils/mkgraph.sh data/lang_test exp/tri1 exp/tri1/graph || exit 1;
steps/decode_nolats.sh --nj 10 --cmd "$decode_cmd" exp/tri1/graph \
  data/dev exp/tri1/decode_dev || exit 1;
fi
fi
if [ $stage -le 7 ]; then
steps/align_si.sh --nj 10 --cmd "$train_cmd" \
  data/train data/lang exp/tri1 exp/tri1_ali || exit 1;
# Train tri2a, which is deltas + delta-deltas
steps/train_deltas.sh --cmd "$train_cmd" 3000 24000 \
  data/train data/lang exp/tri1_ali exp/tri2a || exit 1;
fi

if [ $stage -le 8 ]; then
if $decode; then
$mkgraph_cmd exp/tri2a/log/mkgraph.log \
  utils/mkgraph.sh data/lang_test exp/tri2a exp/tri2a/graph || exit 1;
steps/decode_nolats.sh --nj 10 --cmd "$decode_cmd" exp/tri2a/graph \
  data/dev exp/tri2a/decode_dev || exit 1;
fi
fi

if [ $stage -le 9 ]; then
steps/train_lda_mllt.sh --cmd "$train_cmd" \
  --splice-opts "--left-context=3 --right-context=3" 3500 28000 \
  data/train data/lang exp/tri1_ali exp/tri2b || exit 1;
if $decode; then
$mkgraph_cmd exp/tri2b/log/mkgraph.log \
  utils/mkgraph.sh data/lang_test exp/tri2b exp/tri2b/graph || exit 1;
steps/decode_nolats.sh --nj 10 --cmd "$decode_cmd" exp/tri2b/graph \
  data/dev exp/tri2b/decode_dev || exit 1;
fi
fi

if [ $stage -le 10 ]; then
# Align tri2b system
steps/align_si.sh  --nj 10 --cmd "$train_cmd" \
  --use-graphs true data/train \
  data/lang exp/tri2b exp/tri2b_ali  || exit 1;
# From 2b system, train 3b which is LDA + MLLT + SAT.
steps/train_sat.sh --cmd "$train_cmd" 3500 28000 \
  data/train data/lang exp/tri2b_ali exp/tri3b || exit 1;
if $decode; then
utils/mkgraph.sh data/lang_test \
  exp/tri3b exp/tri3b/graph || exit 1;
steps/decode_fmllr.sh --nj 10 --cmd "$decode_cmd" \
  exp/tri3b/graph data/dev \
  exp/tri3b/decode_dev || exit 1;
fi
fi

if [ $stage -le 11 ]; then
# From 3b system,
steps/align_fmllr.sh --nj 20 --cmd "$train_cmd" \
  data/train data/lang exp/tri3b exp/tri3b_ali || exit 1;
# From 3b system, train another SAT system (tri4a)
steps/train_sat.sh  --cmd "$train_cmd" 4000 32000 \
  data/train data/lang exp/tri3b_ali exp/tri4a || exit 1;

utils/mkgraph.sh data/lang_test \
  exp/tri4a exp/tri4a/graph || exit 1;
steps/decode_fmllr.sh --nj 10 --cmd "$decode_cmd" \
  exp/tri4a/graph data/dev \
  exp/tri4a/decode_dev || exit 1;
fi

if [ $stage -le 12 ]; then
steps/align_fmllr.sh --nj 30 --cmd "$train_cmd" \
  data/train data/lang exp/tri4b exp/tri4b_ali_train || exit 1;
steps/align_fmllr.sh --nj 30 --cmd "$train_cmd" \
  data/dev data/lang exp/tri4b exp/tri4b_ali_dev || exit 1;
fi
exit 0;
if [ $stage -le 13 ]; then
  # getting results (see RESULTS file)
  for x in exp/*/decode*; do [ -d $x ] && grep Sum $x/score_*/*.sys | utils/best_wer.sh; done 2>/dev/null
  for x in exp/*/decode*; do [ -d $x ] && grep WER $x/wer_* | utils/best_wer.sh; done 2>/dev/null
fi
