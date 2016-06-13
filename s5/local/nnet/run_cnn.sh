#!/bin/bash

. ./cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
           ## This relates to the queue.

# This is a shell script, but it's recommended that you run the commands one by
# one by copying and pasting into the shell.
stage=0
tr=data_fbank/train
cv=data_fbank/dev
trcv=data_fbank/all
tr_ali=exp/tri4a_ali_train
cv_ali=exp/tri4a_ali_dev

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

fbankdir=fbank
[ ! -d data_fbank ] && mkdir -p data_fbank
if [ $stage -le 1 ]; then
for x in train dev; do
  steps/make_fbank.sh --cmd "$feat_cmd" --nj 30 --compress true \
    data_fbank/$x exp/make_fbank/$x $fbankdir || exit 1;
  steps/compute_cmvn_stats.sh data_fbank/$x exp/make_fbank/$x $fbankdir || exit 1;
done
exit 0
fi
dir=exp/cnn1d
if [ $stage -le 2 ]; then
  [ ! -d $dir/log ] && mkdir -p $dir/log
  $cuda_cmd $dir/log/train.log \
    ./steps/nnet/train.sh \
      --network-type cnn1d --hid-layers 1 --hid-dim 512 --copy-feats false \
      $tr $cv data/lang $tr_ali $cv_ali $dir || exit 1;
fi
if [ $stage -le 3 ]; then
  ./steps/nnet/align.sh --use-gpu yes --nj 1 --cmd "$cuda_cmd" data_fbank/train data/lang exp/cnn1d exp/cnn1d_ali_train || exit 1
  ./steps/nnet/align.sh --use-gpu yes --nj 1 --cmd "$cuda_cmd" data_fbank/dev data/lang exp/cnn1d exp/cnn1d_ali_dev || exit 1
fi
tr_ali=exp/cnn1d_ali_train
cv_ali=exp/cnn1d_ali_dev
dir=exp/cnn1d_rbm
if [ $stage -le 4 ]; then
  tmp_ft=`mktemp`
  trap "rm -f $tmp_ft" EXIT
  nnet-concat exp/cnn1d/final.feature_transform "nnet-copy --remove-last-components=4 exp/cnn1d/final.nnet - |" $tmp_ft
  if [ ! -d $trcv ]; then
     ./utils/combine_data.sh data_fbank/all data_fbank/train data_fbank/dev || exit 1
  fi
  ./steps/nnet/pretrain_dbn.sh --input-vis-type bern --rbm-extra-opts '--with-bug=false --minibatch-size=3200' --rbm-l2penalty 0 --rbm-iter 3 --copy-feats false --nn-depth 4 --hid-dim 2048 --feature-transform $tmp_ft $trcv $dir
fi
dir=exp/cnn1d_rbm_dnn
if [ $stage -le 5 ]; then
  [ ! -d $dir/log ] && mkdir -p $dir/log
  tmp_ft=`mktemp`
  trap "rm -f $tmp_ft" EXIT
  nnet-concat "nnet-copy --remove-last-components=4 exp/cnn1d/final.nnet - |" exp/cnn1d_rbm/4.dbn $tmp_ft
  $cuda_cmd $dir/log/train.log \
    ./steps/nnet/train.sh \
      --dbn $tmp_ft --network-type dnn --hid-layers 0 --copy-feats false \
      --train-tool-opts "--minibatch-size=512 --randomizer-size=32768 --randomizer-seed=777" \
      $tr $cv data/lang $tr_ali $cv_ali $dir || exit 1;
fi
if [ $stage -le 6 ]; then
  [ ! -d exp/train_denlats/log ] && mkdir -p exp/train_denlats/log
  ./steps/nnet/make_denlats.sh --nj 30 --use-gpu no --cmd "$train_cmd" data_fbank/train data/lang exp/cnn1d_rbm_dnn exp/train_denlats || exit 1
fi
acwt=0.1
dir=exp/cnn1d_rbm_dnn_smbr
if [ $stage -le 7 ]; then
  srcdir=exp/cnn1d_rbm_dnn
  steps/nnet/train_mpe.sh --cmd "$cuda_cmd" --num-iters 8 --acwt $acwt --do-smbr true \
    $tr data/lang $srcdir $tr_ali exp/train_denlats $dir || exit 1
fi
