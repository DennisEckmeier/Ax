FS=450450;
NFFT=[0.001 0.0005 0.00025];
NW=22;
K=43;
PVAL=0.01;

channels=1:4;
f_low=20e3;
f_high=120e3;
conv_size=[15 7];
obj_size=1500;
merge_freq=1;
  merge_freq_overlap=0.9;
  merge_freq_ratio=0.1;
  merge_freq_fraction=0.9;
merge_time=0;
nseg=1;
min_length=0;
