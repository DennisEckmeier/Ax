FS=450450;
NFFT=[0.001 0.0005 0.00025];
%NFFT=0.001;
NW=22;
K=43;
PVAL=0.01;

channels=1:4;
obj_size=1500;
conv_size=[15 7];
f_low=20e3;
f_high=120e3;
nseg=1;
merge_time=[];
merge_freq=0;
  merge_freq_overlap=0.9;
  merge_freq_ratio=0.1;
  merge_freq_fraction=0.9;