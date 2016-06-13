#export KALDI_ROOT=`pwd`/../../..
if [ -d /home/alex/kaldi-keras ]; then
  export KALDI_ROOT=/home/alex/kaldi-keras
else
  export KALDI_ROOT=/usr/local/kaldi-trunk
fi
[ -f $KALDI_ROOT/tools/env.sh ] && . $KALDI_ROOT/tools/env.sh
for d in `ls -d $KALDI_ROOT/src/*bin`; do
  export PATH=$PATH:$d
done
export PATH=$PWD/utils/:$KALDI_ROOT/tools/openfst/bin:$KALDI_ROOT/tools/sph2pipe_v2.5:$PWD:$PATH
#[ ! -f $KALDI_ROOT/tools/config/common_path.sh ] && echo >&2 "The standard file $KALDI_ROOT/tools/config/common_path.sh is not present -> Exit!" && exit 1
[ -f $KALDI_ROOT/tools/config/common_path.sh ] && . $KALDI_ROOT/tools/config/common_path.sh
export LC_ALL=C
