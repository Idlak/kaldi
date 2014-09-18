#!/bin/bash
# Copyright  2014   David Snyder
#            2014   Daniel Povey
# Apache 2.0.
#
# An incomplete run.sh for this example.

. cmd.sh
. path.sh
set -e

mfccdir=`pwd`/mfcc
vaddir=`pwd`/mfcc

# Training data sources
local/make_sre_2008_train.pl /export/corpora5/LDC/LDC2011S05 data
local/make_callfriend.pl /export/corpora/LDC/LDC96S60 vietnamese data
local/make_callfriend.pl /export/corpora/LDC/LDC96S59 tamil data
local/make_callfriend.pl /export/corpora/LDC/LDC96S53 japanese data
local/make_callfriend.pl /export/corpora/LDC/LDC96S52 hindi data
local/make_callfriend.pl /export/corpora/LDC/LDC96S51 german data
local/make_callfriend.pl /export/corpora/LDC/LDC96S50 farsi data
local/make_callfriend.pl /export/corpora5/LDC/LDC96S48 french data
local/make_callfriend.pl /export/corpora5/LDC/LDC96S49 arabic.standard data
local/make_callfriend.pl /export/corpora5/LDC/LDC96S54 korean data
local/make_callfriend.pl /export/corpora5/LDC/LDC96S55 chinese.mandarin.mainland data
local/make_callfriend.pl /export/corpora5/LDC/LDC96S56 chinese.mandarin.taiwan data
local/make_callfriend.pl /export/corpora5/LDC/LDC96S57 spanish.caribbean data
local/make_callfriend.pl /export/corpora5/LDC/LDC96S58 spanish.noncaribbean data
local/make_lre96.pl /export/corpora/NIST/lid96e1 data
local/make_lre03.pl /export/corpora4/LDC/LDC2006S31 data
local/make_lre05.pl /export/corpora5/LDC/LDC2008S05 data
local/make_lre07_train.pl /export/corpora5/LDC/LDC2009S05 data
local/make_lre09.pl /export/corpora5/NIST/LRE/LRE2009/eval data

# Evaluation data set
local/make_lre07.pl /export/corpora5/LDC/LDC2009S04 data/lre07

src_list="data/sre08_train_10sec_female \
    data/sre08_train_10sec_male data/sre08_train_3conv_female \
    data/sre08_train_3conv_male data/sre08_train_8conv_female \
    data/sre08_train_8conv_male data/sre08_train_short2_male \
    data/sre08_train_short2_female data/ldc96* data/lid05d1 \
    data/lid05e1 data/lid96d1 data/lid96e1 data/lre03 \
    data/ldc2009* data/lre09"

# Remove any spk2gender files that we have: since not all data
# sources have this info, it will cause problems with combine_data.sh
for d in $src_list; do rm -f $d/spk2gender 2>/dev/null; done

utils/combine_data.sh data/train_unsplit $src_list

# original utt2lang will remain in data/train_unsplit/.backup/utt2lang.
utils/apply_map.pl -f 2 --permissive local/lang_map.txt  < data/train_unsplit/utt2lang  2>/dev/null > foo
cp foo data/train_unsplit/utt2lang
echo "**Language count in training:**"
awk '{print $2}' foo | sort | uniq -c | sort -nr
rm foo

local/split_long_utts.sh --max-utt-len 120 data/train_unsplit data/train

# This commented script is an alternative to the above utterance
# splitting method. Here we split the utterance based on the number of 
# frames which are voiced, rather than the total number of frames.
# max_voiced=3000 
# local/vad_split_utts.sh --max-voiced $max_voiced data/train_unsplit $mfccdir data/train

use_vtln=true
if $use_vtln; then
  for t in train lre07; do
    cp -r data/${t} data/${t}_novtln
    rm -r data/${t}_novtln/{split,.backup,spk2warp} 2>/dev/null || true
    steps/make_mfcc.sh --mfcc-config conf/mfcc_vtln.conf --nj 100 --cmd "$train_cmd" \
       data/${t}_novtln exp/make_mfcc $mfccdir 
    lid/compute_vad_decision.sh data/${t}_novtln exp/make_mfcc $mfccdir
  done

  # Vtln-related things:
  # We'll use a subset of utterances to train the GMM we'll use for VTLN
  # warping.
  utils/subset_data_dir.sh data/train_novtln 5000 data/train_5k_novtln

  # Note, we're using the speaker-id version of the train_diag_ubm.sh script, which
  # uses double-delta instead of SDC features to train a 256-Gaussian UBM.
  sid/train_diag_ubm.sh --nj 30 --cmd "$train_cmd" data/train_5k_novtln 256 \
    exp/diag_ubm_vtln
  lid/train_lvtln_model.sh --mfcc-config conf/mfcc_vtln.conf --nj 30 --cmd "$train_cmd" \
     data/train_5k_novtln exp/diag_ubm_vtln exp/vtln

  for t in lre07 train; do
    lid/get_vtln_warps.sh --nj 100 --cmd "$train_cmd" \
       data/${t}_novtln exp/vtln exp/${t}_warps
    cp exp/${t}_warps/utt2warp data/$t/
  done
fi


utils/fix_data_dir.sh data/train
utils/filter_scp.pl data/train/utt2warp data/train/utt2spk > data/train/utt2spk_tmp
cp data/train/utt2spk_tmp data/train/utt2spk
utils/fix_data_dir.sh data/train


steps/make_mfcc.sh --mfcc-config conf/mfcc.conf --nj 100 --cmd "$train_cmd" \
  data/train exp/make_mfcc $mfccdir
steps/make_mfcc.sh --mfcc-config conf/mfcc.conf --nj 40 --cmd "$train_cmd" \
  data/lre07 exp/make_mfcc $mfccdir

lid/compute_vad_decision.sh --nj 4 --cmd "$train_cmd" data/train \
  exp/make_vad $vaddir
lid/compute_vad_decision.sh --nj 4 --cmd "$train_cmd" data/lre07 \
  exp/make_vad $vaddir


utils/subset_data_dir.sh data/train 5000 data/train_5k
utils/subset_data_dir.sh data/train 10000 data/train_10k


lid/train_diag_ubm.sh --nj 30 --cmd "$train_cmd" data/train_5k 2048 \
  exp/diag_ubm_2048
lid/train_full_ubm.sh --nj 30 --cmd "$train_cmd" data/train_10k \
  exp/diag_ubm_2048 exp/full_ubm_2048_10k

lid/train_full_ubm.sh --nj 30 --cmd "$train_cmd" data/train \
  exp/full_ubm_2048_10k exp/full_ubm_2048

# Alternatively, a diagonal UBM can replace the full UBM used above.
# The preceding calls to train_diag_ubm.sh and train_full_ubm.sh
# can be commented out and replaced with the following lines.
# 
# This results in a slight degradation but could improve error rate when
# there is less training data than used in this example.
#
#lid/train_diag_ubm.sh --nj 30 --cmd "$train_cmd" data/train 2048 \
#  exp/diag_ubm_2048
#
#gmm-global-to-fgmm exp/diag_ubm_2048/final.dubm \
#  exp/full_ubm_2048/final.ubm


lid/train_ivector_extractor.sh --cmd "$train_cmd -l mem_free=2G,ram_free=2G" \
  --num-iters 5 exp/full_ubm_2048/final.ubm data/train \
  exp/extractor_2048

lid/extract_ivectors.sh --cmd "$train_cmd -l mem_free=3G,ram_free=3G" --nj 50 \
   exp/extractor_2048 data/train exp/ivectors_train

lid/extract_ivectors.sh --cmd "$train_cmd -l mem_free=3G,ram_free=3G" --nj 50 \
   exp/extractor_2048 data/lre07 exp/ivectors_lre07

lid/run_logistic_regression.sh --config conf/logistic-regression.conf \
  --prior-scale 0.75

# Training error-rate
# ER (%): 6.65

# General LR 2007 closed-set eval
local/lre07_logistic_regression_eval.sh \
  exp/ivectors_train/logistic_regression_rebalanced
# Duration (sec):    avg      3     10     30
#        ER (%):  28.50  49.10  24.52  11.87
#     C_avg (%):  15.16  27.96  12.86   4.65
