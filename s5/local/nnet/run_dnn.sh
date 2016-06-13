#!/bin/bash

. ./cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
           ## This relates to the queue.

# This is a shell script, but it's recommended that you run the commands one by
# one by copying and pasting into the shell.
stage=0
tr=data/train
cv=data/dev
trcv=data/all
tr_ali=exp/tri4a_ali_train
cv_ali=exp/tri4a_ali_dev

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

mfccdir=mfcc/hires
if [ $stage -le 1 ]; then
for x in train dev ami; do
  ./utils/copy_data_dir.sh data/$x data_hires/$x
  steps/make_mfcc.sh --cmd "$train_cmd" --nj 30 --compress true --mfcc-config conf/mfcc_hires.conf \
    data_hires/$x exp/make_mfcc/hires/$x $mfccdir || exit 1;
  steps/compute_cmvn_stats.sh data_hires/$x exp/make_mfcc/hires/$x $mfccdir || exit 1;
done
./utils/combine_data.sh data_hires/all data_hires/train data_hires/dev || exit 1;

fi
tr=data_hires/train
cv=data_hires/dev
if [ $stage -le 2 ]; then
steps/train_lda_mllt.sh --cmd "$train_cmd" \
  --num-iters 13 --splice-opts "--left-context=3 --right-context=3" 3500 28000 \
  $tr data/lang exp/tri1_ali exp/tri2c || exit 1;
fi
if [ $stage -le 3 ]; then
# Align tri2c system
steps/align_si.sh  --nj 10 --cmd "$train_cmd" \
  --use-graphs true $tr \
  data/lang exp/tri2c exp/tri2c_ali  || exit 1;
# From 2c system, train 3c which is LDA + MLLT + SAT.
steps/train_sat.sh --cmd "$train_cmd" 3500 28000 \
  $tr data/lang exp/tri2c_ali exp/tri3c || exit 1;

fi
if [ $stage -le 4 ]; then
# From 3c system,
steps/align_fmllr.sh --nj 20 --cmd "$train_cmd" \
  $tr data/lang exp/tri3c exp/tri3c_ali || exit 1;
# From 3c system, train another SAT system (tri4c)
steps/train_sat.sh  --cmd "$train_cmd" 4000 32000 \
  $tr data/lang exp/tri3c_ali exp/tri4c || exit 1;
fi
if [ $stage -le 5 ]; then
for x in train dev ami; do
steps/align_fmllr.sh --nj 30 --cmd "$train_cmd" \
  data_hires/$x data/lang exp/tri4c exp/tri4c_ali_$x || exit 1;
done
fi

if [ $stage -le 6 ]; then
for x in train dev ami; do
./steps/nnet/make_fmllr_feats.sh --nj 30 --cmd "$train_cmd" \
  --transform-dir exp/tri4c_ali_${x} \
  data_fmllr/${x} data_hires/${x} exp/tri4c exp/make_fmllr/${x} mfcc/hires/fmllr || exit 1
done
./utils/combine_data_dir.sh data_fmllr/all data_fmllr/train data_fmllr/dev
fi
tr=data_fmllr/train
cv=data_fmllr/dev
trcv=data_fmllr/all
tr_ali=exp/tri4c_ali_train
cv_ali=exp/tri4c_ali_dev
dir=exp/rbm
if [ $stage -le 7 ]; then
[ ! -d $dir/log ] && mkdir -p $dir/log
$cuda_cmd $dir/log/training.log \
  ./steps/nnet/pretrain_dbn.sh --rbm-extra-opts \"--with-bug=false --minibatch-size=3200\" \
    --rbm-l2penalty 0 --rbm-iter 2 --copy-feats false --nn-depth 2 --hid-dim 2048 $trcv $dir
fi

if [ $stage -le 8 ]; then
for x in train dev ami; do
./utils/copy_data_dir.sh data/$x data_merge/$x
paste-feats scp:data_fmllr/$x/feats.scp scp:data_hires/$x/feats.scp ark:- | \
copy-feats --compress=true ark:- ark,scp:data_merge/$x/feats.ark,data_merge/$x/feats.scp
done
./utils/combine_data.sh data_merge/all data_merge/train data_merge/dev || exit 1;
fi
tr=data_merge/train
cv=data_merge/dev
trcv=data_merge/all
dir=exp/rbm_merge
if [ $stage -le 9 ]; then
[ ! -d $dir/log ] && mkdir -p $dir/log
nnet-copy --remove-last-components=4 exp/cnn1d/final.nnet $dir/left.nnet
cat << EOF | nnet-initialize - $dir/merge.nnet
<NnetProto>
<ParallelComponent> <InputDim> 80 <OutputDim> 880 <NestedNnetFilename> exp/cnn1d/final.feature_transform exp/rbm/final.feature_transform </NestedNnetFilename>
<ParallelComponent> <InputDim> 880 <OutputDim> 4096 <NestedNnetFilename> $dir/left.nnet exp/rbm/2.dbn </NestedNnetFilename>
</NnetProto>
EOF
$cuda_cmd $dir/log/training.log \
  ./steps/nnet/pretrain_dbn.sh --rbm-extra-opts \"--with-bug=false --minibatch-size=3200\" \
    --feature-transform $dir/merge.nnet \
    --rbm-lrate 0.008 --input-vis-type bern --rbm-l2penalty 0 --rbm-iter 2 --copy-feats false --nn-depth 4 --hid-dim 2048 $trcv $dir
fi
dir=exp/rbm_merge_dnn
if [ $stage -le 10 ]; then
[ ! -d $dir/log ] && mkdir -p $dir/log
nnet-copy --remove-last-components=1 exp/rbm_merge/merge.nnet $dir/feature_transform
nnet-copy --remove-first-components=1 exp/rbm_merge/merge.nnet - | nnet-concat - exp/rbm_merge/4.dbn $dir/dbn
$cuda_cmd $dir/log/training.log \
./steps/nnet/train.sh \
    --dbn $dir/dbn --network-type dnn --hid-layers 0 --copy-feats false \
    --feature-transform $dir/feature_transform \
    --train-tool-opts "--minibatch-size=1024 --randomizer-size=32768 --randomizer-seed=777" \
    $tr $cv data/lang $tr_ali $cv_ali $dir || exit 1;
fi
dir=exp/rbm_merge_dnn_denlats
if [ $stage -le 11 ]; then
  [ ! -d $dir/log ] && mkdir -p $dir/log
  $train_cmd $dir/log/mkdenlats.log \
    ./steps/nnet/make_denlats.sh --nj 30 --cmd "$train_cmd" --use-gpu no $trcv data/lang exp/rbm_merge_dnn $dir || exit 1
fi
acwt=0.1
dir=exp/rbm_merge_dnn_smbr
if [ $stage -le 12 ]; then
  [ ! -d exp/tri4c_ali_all ] && ./utils/combine_ali_dirs.sh data_merge/all exp/tri4c_ali_all exp/tri4c_ali_train exp/tri4c_ali_dev
  latdir=exp/rbm_merge_dnn_denlats
  srcdir=exp/rbm_merge_dnn
  steps/nnet/train_mpe.sh --cmd "$cuda_cmd" --num-iters 6 \
    --acwt $acwt --do-smbr true --momentum 0.9 \
    $trcv data/lang $srcdir exp/tri4c_ali_all $latdir $dir || exit 1
fi
