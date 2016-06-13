#!/bin/bash
. ./cmd.sh
. ./path.sh
#./steps/make_fbank.sh --cmd "$train_cmd" --nj 30 \
#  data_fbank/ami exp/make_fbank fbank || exit 1

$cuda_cmd ami.log \
./steps/nnet/decode.sh \
  --config conf/decode_dnn.conf --nj 1 --use-gpu yes \
  --nnet exp/cnn1d_rbm_dnn_smbr/8.nnet --acwt 0.1 \
  exp/tri4a/graph data_fbank/ami exp/cnn1d_rbm_dnn_smbr/decode_ami || exit 1
