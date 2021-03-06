% function ax1(params_file,FILENAME,SUFFIX)
% function ax1(params_file,FILENAME,SUFFIX,START,STOP)
% function ax1(FS,NFFT,NW,K,PVAL,FILENAME,SUFFIX)
% function ax1(FS,NFFT,NW,K,PVAL,FILENAME,SUFFIX,START,STOP)
%
% analyze a set of time series with multi-taper spectral analysis and
% create a sparse matrix of just the time-frequency pixels whose F-test
% passes PVAL.
%
% typical usage consists of one or more microphones being analyzed by one
% or more parameter sets.  for example, four microphone recordings of the
% same vocalizing mouse analyzed with three different NFFTs and the same
% NW, K, and PVAL.  e.g. <filename>.wav yields <filename>-[1-3].ax
%
% FS: sampling rate in Hertz
% NFFT: FFT window size in tics.  a power of 2 is advised
% NW: multi-taper time-bandwidth product
% K: number of tapers
% PVAL: F-test p-val threshold
% FILENAME: the full path to a single .wav or .bin file containing all channels,
%   or of .ch[0-9] files, w/o the suffix, each with a single channel of float32s
% SUFFIX: a string to append to FILENAME to differentiate parameter sets used
% START,STOP: optional time range, in seconds
%
% output is a binary file with a time x frequency x amplitude x channel
%     array of hot pixels
%
% ax1('./parameters.txt','~/nobel/prize/data.wav','0');
% ax1(200e3,32,3,5,0.01,'/dir/full/of/wav/files/','0');
% ax1(450450,64,6,11,0.01,'~/groundtruth/','0',0,60);

function ax1(varargin)

if((nargin~=3)&&(nargin~=5)&&(nargin~=7)&&(nargin~=9))
  error('invalid args');
end

close_it=0;
if((exist('parpool')==2) && (length(gcp)==0))
  try
    if(isdeployed)
      parpool(16);
    else
      parpool;
    end
    close_it=1;
  catch
    disp('WARNING: could not open parallel pool of workers.  proceeding with a single thread.');
  end
end

tstart=tic;

if(nargin<6)
  fid=fopen(varargin{1},'r');
  eval(fread(fid,'*char')');
  fclose(fid);
  FILENAME=varargin{2};
  SUFFIX=varargin{3};
else
  FS=varargin{1};
  NFFT=varargin{2};
  NW=varargin{3};
  K=varargin{4};
  PVAL=varargin{5};
  FILENAME=varargin{6};
  SUFFIX=varargin{7};
end
if((nargin==5)||(nargin==9))
  START=varargin{end-1};
  STOP=varargin{end};
end

if(ischar(FS))        FS=str2num(FS);              end
if(ischar(NFFT))      NFFT=str2num(NFFT);          end
if(ischar(NW))        NW=str2num(NW);              end
if(ischar(K))         K=str2num(K);                end
if(ischar(PVAL))      PVAL=str2num(PVAL);          end
if((nargin==5)||(nargin==9))
  if(ischar(START))   START=str2num(START);        end
  if(ischar(STOP))    STOP=str2num(STOP);          end
end

if(length(NFFT)>1)
  error('multiple NFFTs not supported when calling ax1() from the matlab command line');
end

use_hdf5=1;

if(use_hdf5)
  VERSION=get_version();
  TIMESTAMP=datestr(now,30);
else
  VERSION=1;
end

SUBSAMPLE=1;
NWORKERS=0;
if(exist('parpool')==2)
  gcp('nocreate');
  NWORKERS=ans.NumWorkers;
end
if(NWORKERS==0)  NWORKERS=1;  end

FS=FS/SUBSAMPLE;

log2(NFFT);
if(abs(ans-round(ans))>eps(ans))
  warning('ax1 will be faster if NFFT is a power of 2');
end
NFFT/2;
if(abs(ans-round(ans))>eps(ans))
  error('NFFT must be even');
end
NWINDOWS_PER_WORKER=round(12*256*1000/NFFT);  % NFFT/2 ticks

[tapers,eigs]=dpss(NFFT,NW,K);

f=(0:(NFFT/2))*FS/NFFT;
df=f(2)-f(1);

sig=finv(1-PVAL/NFFT,2,2*K-2); % F-distribution based 1-p% point

[FILEPATH,tmp,FILETYPE]=fileparts(FILENAME);
FILENAME=fullfile(FILEPATH,tmp);
if(exist([FILENAME FILETYPE])==2)
  FILEPATH='';
  FILENAMES=[];
  try
    if strcmp(FILETYPE,'.wav')
      info=audioinfo([FILENAME FILETYPE]);
    elseif strcmp(FILETYPE,'.bin')
      fid = fopen([FILENAME FILETYPE], 'r');
      version=fread(fid, 1, 'double');
      info.SampleRate = fread(fid, 1, 'double');
      info.NumChannels = fread(fid, 1, 'double');
      switch version
        case 1
          first=ftell(fid);
          fseek(fid,0,'eof');
          last=ftell(fid);
          info.TotalSamples=(last-first+1)/8/info.NumChannels;
        case 2
          first=ftell(fid);
          fseek(fid,0,'eof');
          last=ftell(fid);
          info.TotalSamples=(last-first+1)/4/info.NumChannels;
        case 3
          tmp=fread(fid,[2 info.NumChannels],'double');
          step=tmp(1,info.NumChannels);
          offset=tmp(2,info.NumChannels);
          fread(fid, obj.channel-1, 'int16');  % skip over first channels
          first=ftell(fid);
          fseek(fid,0,'eof');
          last=ftell(fid);
          info.TotalSamples=(last-first+1)/2/info.NumChannels;
      end
      fclose(fid);
    else
      error(['don''t know filetype ''' FILETYPE '''']);
    end
  catch
    error(['can''t open file ''' FILENAME '''']);
  end
  FILELEN_TIC=info.TotalSamples;
  NCHANNELS=info.NumChannels;
  if info.SampleRate~=FS
    warning(['sampling rates in argument list (' num2str(FS) ') and file (' num2str(info.SampleRate) ...
        ') do not match;  continuing with ' num2str(info.SampleRate)]);
    FS=info.SampleRate;
  end
  REMAP=1:NCHANNELS;
else
  FILETYPE='.ch';
  FILENAMES=dir([FILENAME '.ch*']);
  NCHANNELS=length(FILENAMES);
  if(NCHANNELS==0)
    error(['can''t find any .ch files with basename ' FILENAME]);
  end
  for i=1:NCHANNELS
    filei=fullfile(FILEPATH,FILENAMES(i).name);
    fid=fopen(filei,'r');
    if(fid==-1)
      error(['can''t open file ''' filei '''']);
    end
    fseek(fid,0,1);
    ftell(fid)/4;
    if((i>1)&&(ans~=FILELEN_TIC))  error('not all file lengths are the same');  end
    FILELEN_TIC=ans;
    REMAP(i)=str2num(FILENAMES(i).name(end));
    fclose(fid);
  end    
end
FILELEN=FILELEN_TIC/FS;

if(~exist('START','var'))
  START_TIC=0;
  STOP_TIC=FILELEN_TIC;
else
  START_TIC=round(START*FS/(NFFT/2))*(NFFT/2);
  STOP_TIC=round(STOP*FS);
end
tmp=round((STOP_TIC-START_TIC)/(NFFT/2)-1);
disp(['Processing ' num2str(NCHANNELS) ' channels x ' num2str((STOP_TIC-START_TIC)/FS/60,3) ' min = ' num2str(tmp) ...
    ' windows = ' num2str(tmp/NWINDOWS_PER_WORKER,3) ' chunks of data in ' FILENAME FILETYPE]);

if(use_hdf5)
  if(exist([FILENAME '-' SUFFIX '.ax'],'file'))  delete([FILENAME '-' SUFFIX '.ax']);  end
  h5create([FILENAME '-' SUFFIX '.ax'],'/hotPixels',[Inf 4],'ChunkSize',[1024 4]);
  h5writeatt([FILENAME '-' SUFFIX '.ax'],'/hotPixels','VERSION',VERSION);
  h5writeatt([FILENAME '-' SUFFIX '.ax'],'/hotPixels','TIMESTAMP',TIMESTAMP);
  h5writeatt([FILENAME '-' SUFFIX '.ax'],'/hotPixels','FS',FS);
  h5writeatt([FILENAME '-' SUFFIX '.ax'],'/hotPixels','NFFT',NFFT);
  h5writeatt([FILENAME '-' SUFFIX '.ax'],'/hotPixels','NW',NW);
  h5writeatt([FILENAME '-' SUFFIX '.ax'],'/hotPixels','K',K);
  h5writeatt([FILENAME '-' SUFFIX '.ax'],'/hotPixels','PVAL',PVAL);
  h5writeatt([FILENAME '-' SUFFIX '.ax'],'/hotPixels','FILENAME',FILENAME);
  h5writeatt([FILENAME '-' SUFFIX '.ax'],'/hotPixels','SUFFIX',SUFFIX);
  if(exist('START'))  h5writeatt([FILENAME '-' SUFFIX '.ax'],'/hotPixels','START',START);  end
  if(exist('STOP'))   h5writeatt([FILENAME '-' SUFFIX '.ax'],'/hotPixels','STOP',STOP);    end
  h5writeatt([FILENAME '-' SUFFIX '.ax'],'/hotPixels','NWORKERS',NWORKERS);
  h5writeatt([FILENAME '-' SUFFIX '.ax'],'/hotPixels','NWINDOWS_PER_WORKER',NWINDOWS_PER_WORKER);
else
  fid_out=fopen([FILENAME '-' SUFFIX '.ax'],'w');
  fwrite(fid_out,uint8([VERSION SUBSAMPLE NWINDOWS_PER_WORKER]),'uint8');  % CHUNK not necessary
  fwrite(fid_out,uint32([FS NFFT]),'uint32');
  fwrite(fid_out,uint16([NW K]),'uint16');
  fwrite(fid_out,[PVAL df],'double');
end

k=1;
t=START_TIC;
tic;
while(t<STOP_TIC)
  if(toc>10)
    disp([num2str(round((t-START_TIC)/FS)) ' sec processed;  '...
        num2str(round(100*(t-START_TIC)/(STOP_TIC-START_TIC))) '% done']);
    tic;
  end

  idx=cell(1,NWORKERS);
  parfor i=1:NWORKERS
%   for i=1:NWORKERS
    dd=[];
    NSAMPLES = NFFT/2*(NWINDOWS_PER_WORKER+1);
    tmp=t+(i-1)*NFFT/2*NWINDOWS_PER_WORKER;
    if(tmp>=STOP_TIC)  continue;  end
    switch FILETYPE
      case '.ch'
        for j=1:NCHANNELS
          fid = fopen(fullfile(FILEPATH,FILENAMES(j).name),'r');
          fseek(fid,tmp*4,-1);
          dd(:,j) = fread(fid, NSAMPLES, 'float32', 4*(SUBSAMPLE-1));
          fclose(fid);
        end
      case {'.wav','.WAV'}
        dd=audioread([FILENAME FILETYPE],[tmp+1 min(tmp+NSAMPLES, FILELEN_TIC)]);
      case '.bin'
        dd=binread([FILENAME FILETYPE],[tmp+1 min(tmp+NSAMPLES, FILELEN_TIC)]);
    end
    dd=single(dd);
    if(size(dd,1)<NSAMPLES)
      dd=[dd; zeros(NSAMPLES-size(dd,1), NCHANNELS, 'single')];
    end

    for j=1:NWINDOWS_PER_WORKER
      ddd=dd((1:NFFT)+NFFT/2*(j-1),:);
      F = ftestc(ddd,tapers,PVAL);
      for l=1:NCHANNELS
        tmp=1+find(F(2:end-1,l)'>sig);
        for m=1:length(tmp)
          [freq,amp]=brown_puckette(ddd(:,l)',tmp(m),FS);
          idx{i}(end+1,:) = [t/(NFFT/2)+(i-1)*NWINDOWS_PER_WORKER+j, freq, amp, l];
        end
      end
    end
  end
  
  for i=1:length(idx)
    if(isempty(idx{i}))  continue;  end
    idx{i}(:,4)=REMAP(idx{i}(:,4));
    %tmp=[i{1}(:,1:3) REMAP(i{1}(:,4))];
    if(use_hdf5)
      h5write([FILENAME '-' SUFFIX '.ax'],'/hotPixels',idx{i},[k 1],size(idx{i}));
      k=k+size(idx{i},1);
    else
      fwrite(fid_out,idx{i}','double');
    end
  end

  t = t+NFFT/2*NWINDOWS_PER_WORKER*NWORKERS;
end

if(~use_hdf5)
  fwrite(fid_out,'Z','uchar');
  fclose(fid_out);
end

tstop=toc(tstart);
disp(['Run time was ' num2str(tstop/60,3) ' minutes.']);

if((exist('parpool')==2) && (length(gcp)>0) && close_it)
  try
    delete(gcp('nocreate'));
  catch
    disp('WARNING: could not close parallel pool of workers.  exiting anyway.');
  end
end



% from Chronux
function Fval = ftestc(data,tapers,pval)
[NC,C]=size(data);
[NK,K]=size(tapers);
N=NC;

Kodd=1:2:K;
Keven=2:2:K;

data=permute(data,[1 3 2]);
data_proj=bsxfun(@times,data,tapers);
J=fft(data_proj,N);

Jp=J(1:(N/2+1),Kodd,:);                     % f x K x C
H0 = sum(tapers(:,Kodd),1);                 % 1 x K
H0sq = sum(H0.*H0);                         % 1
JpH0=squeeze(sum(bsxfun(@times,Jp,H0),2));  % f x C
A=JpH0./H0sq;                               % f x C
Kp=size(Jp,2);
Ap=permute(A,[1 3 2]);                      % f x 1 x C
Jhat=bsxfun(@times, Ap, H0);

num=(K-1).*(abs(A).^2).*H0sq;
den1=Jp-Jhat;
den1=real(den1).*real(den1)+imag(den1).*imag(den1);
den1=squeeze(sum(den1,2));
den2=J(1:(N/2+1),Keven,:);
den2=real(den2).*real(den2)+imag(den2).*imag(den2);
den2=squeeze(sum(den2,2));
den = den1 + den2;
Fval=num./den;



% from charpentier (1986) and brown and puckette (1993; JASA)
function [freq,amp]=brown_puckette(x,k,fs)

nfft=length(x);
X=fft(x);
Xh0=0.5*(X(k)-0.5*X(k+1)-0.5*X(k-1));
Xh1=0.5*exp(sqrt(-1)*2*pi*(k-1)/nfft)*...
   (X(k) - 0.5*exp(sqrt(-1)*2*pi/nfft)*X(k+1)...
         - 0.5*exp(-sqrt(-1)*2*pi/nfft)*X(k-1));
phi0=atan2(imag(Xh0),real(Xh0));
phi1=atan2(imag(Xh1),real(Xh1));
if((phi1-phi0)<0)  phi1=phi1+2*pi;  end
freq=(phi1-phi0)*fs/(2*pi);

period = fs/freq;
last = floor(period * floor(length(x)/period));
real_part = mean(x(1:last) .* cos([1:last]*(2*pi/period)));
imag_part = mean(x(1:last) .* sin([1:last]*(2*pi/period)));
amp = 2*abs(real_part + i*imag_part);
