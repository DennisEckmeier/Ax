%function ax2(f_low, f_high, conv_size, obj_size, ...
%    merge_freq, merge_freq_overlap, merge_freq_ratio, merge_freq_fraction, ...
%    merge_time, nseg, min_length, ...
%    channels, data_path)
%function ax2(params_file, data_path)
%
%f_low, f_high are in Hz
%conv_size is [height_freq width_time] in pixels, each must be odd
%obj_size is in pixels
%set merge_freq to 1 to collapse harmonically related syllables, 0 otherwise
%merge_freq_overlap is the fraction in time two segments must overlap
%merge_freq_ratio is the tolerance in frequency ratio two segments must be within
%merge_freq_fraction is the fraction of the overlap the must be within the tolerance
%merge_time is the maximum gap length, in seconds, below which vocalizations
%  are combined;  use 0 to not combine
%nseg is the minimum number of merged segements a vocalization must contain
%min_length is the minimum syllable length in sec
%channels is a vector of which channels to use, or [] to use all of them (except 5 of course)
%data_path can be to a folder or to a set of files.  for the latter, omit the .ch* suffix
%
%three files are output:
%.voc: an Mx4 array whose columns are the start & stop times (sec), and low & high frequences (Hz)
%.fc: a cell array (vocalizations) of cell arrays (syllables) of Nx3 arrays (time[s], freq[Hz], amplitude)
%.params: a .m file of the parameters used

%for ultrasonic:
%ax2(20e3, 120e3, [15 7], 1500, 0, 0.9, 0.1, 0.9, 0, 1, 0,...
%    1:4, '/groups/egnor/egnorlab/for_ben/sys_test_07052012a/demux/');
%ax2('ultrasonic_params.m', '/groups/egnor/egnorlab/for_ben/sys_test_07052012a/demux/');
%
%for rejection:
%ax2(1e3, 20e3, [15 7], 1000, 0, 0.9, 0.1, 0.9, 0, 3, 0,...
%    1:4, '/groups/egnor/egnorlab/for_ben/sys_test_07052012a/demux/');
%ax2('rejection_params.m', '/groups/egnor/egnorlab/for_ben/sys_test_07052012a/demux/');

function ax2(varargin)

switch nargin
  case 2
    run(varargin{1});
    data_path=varargin{2};
  case 13
    f_low=varargin{1};
    f_high=varargin{2};
    conv_size=varargin{3};
    obj_size=varargin{4};
    merge_freq=varargin{5};
    merge_freq_overlap=varargin{6};
    merge_freq_ratio=varargin{7};
    merge_freq_fraction=varargin{8};
    merge_time=varargin{9};
    nseg=varargin{10};
    min_length=varargin{11};
    channels=varargin{12};
    data_path=varargin{13};
  otherwise
    error('invalid args');
end

tmp=dir(fullfile(data_path,'*.ax'));
if(~isempty(tmp))
  datafiles=cell(1,length(tmp));
  for i=1:length(tmp)
    [~,datafiles{i},~]=fileparts(tmp(i).name(1:end-7));
  end
  datafiles=unique(datafiles);
  if(length(datafiles)>1)
    if(exist('matlabpool')==2 && matlabpool('size')==0)
      matlabpool open
    end
  end
  parfor i=1:length(datafiles)
  %for i=1:length(datafiles)
    ax2_guts(i, f_low, f_high, conv_size, obj_size, ...
        merge_freq, merge_freq_overlap, merge_freq_ratio, merge_freq_fraction, ...
        merge_time, nseg, min_length, channels, fullfile(data_path, datafiles{i}));
  end
else
  tmp=dir([data_path '*.ax']);
  if(~isempty(tmp))
    ax2_guts(0, f_low, f_high, conv_size, obj_size, ...
        merge_freq, merge_freq_overlap, merge_freq_ratio, merge_freq_fraction, ...
        merge_time, nseg, min_length, channels, data_path);
  else
    error(['can''t find ' data_path]);
  end
end


function ax2_guts(num, F_LOW, F_HIGH, CONV_SIZE, OBJ_SIZE, ...
    MERGE_FREQ, MERGE_FREQ_OVERLAP, MERGE_FREQ_RATIO, MERGE_FREQ_FRACTION, ...
    MERGE_TIME, NSEG, MIN_LENGTH, CHANNELS, filename)

GROUNDTRUTH=0;
SAVE_WAV=0;
SAVE_PNG=0;
if(isempty(CHANNELS))  CHANNELS=[1:4 6:8];  end

if(SAVE_WAV || SAVE_PNG)
  figure;
  get(gcf,'position');
  set(gcf,'position',[ans(1) ans(2) 4*ans(3) ans(4)]);
  subplot('position',[0.05 0.1 0.9 0.8]);
  set(gca,'color',[0 0 0]);
end

%load header
disp([num2str(num) ': ' 'processing file ' filename]);
tmp=dir([filename,'*.ax']);
for i=1:length(tmp)
  disp([num2str(num) ': loading ' tmp(i).name]);
  fid(i)=fopen(fullfile(fileparts(filename),tmp(i).name));
  data(i).VERSION=fread(fid(i),1,'uint8');
  data(i).SUBSAMPLE=fread(fid(i),1,'uint8');
  data(i).CHUNK=fread(fid(i),1,'uint8');
  data(i).FS=fread(fid(i),1,'uint32');
  if((i>1) && (data(i).FS~=data(1).FS))
    error('sampling frequencies are not the same');
  end
  data(i).NFFT=fread(fid(i),1,'uint32');
  data(i).NW=fread(fid(i),1,'uint16');
  data(i).K=fread(fid(i),1,'uint16');
  data(i).PVAL=fread(fid(i),1,'double');
  data(i).df=fread(fid(i),1,'double');
  len=ftell(fid(i));
  fseek(fid(i),-1,'eof');
  if(~strcmp(char(fread(fid(i),1,'uchar')),'Z'))
    error('end of file marker missing.  file corrupt');
  end
  fseek(fid(i),len,'bof');
end
[~,idx]=sort([data.NFFT]);  data=data(idx);  fid=fid(idx);

df=min([data.df])/10;
minNFFT=min([data.NFFT]);
maxNFFT=max([data.NFFT]);
FS=data(1).FS;
CHUNK_TIME_SEC=10;  % sec
CHUNK_TIME_WINDOWS=round(CHUNK_TIME_SEC*FS/(maxNFFT/2))*maxNFFT./[data.NFFT];  % in units of windows
skytruth=[];
freqtruth={};
MERGE_TIME=MERGE_TIME*FS/minNFFT*2;
voc_num=1;
hit_num=1;
miss_num=1;
fa_num=1;
CHUNK_FILE=1024;

if(GROUNDTRUTH)
  groundtruth=load([filename '.gnd']);
  groundtruth=groundtruth(:,2:3);
  groundtruth=sortrows(groundtruth,1);
  groundtruth=groundtruth./FS;
  idx=find(groundtruth(:,1)>groundtruth(:,2));
  if(~isempty(idx))
    error(['rows ' num2str(idx) ' of groundtruth are invalid.']);
  end
  groundtruth(:,3)=0;
  sidx=1;  gidx=1;
end

tic;
eof=false;  count=4*CHUNK_FILE;
chunk_curr=1;
while ~eof
  if(toc>10)  disp([num2str(num) ': ' num2str(chunk_curr*CHUNK_TIME_SEC) ' sec chunk']);  tic;  end;
  eof=(max(count)<4*CHUNK_FILE);

  %collapse across channels and window sizes
  if ~eof
    for i=1:length(data)
      tmp=[];  data(i).MT_next=[];
      while ~feof(fid(i))
        [foo,count(i)]=fread(fid(i),[4 CHUNK_FILE],'double');
        tmp=[tmp; foo'];
        idx=find(tmp(:,1)>chunk_curr*CHUNK_TIME_WINDOWS(i),1);
        if(feof(fid(i)) && isempty(idx))
          idx=size(tmp,1)+1;
        end
        if(~isempty(idx))
          idx2=find((tmp(1:(idx-1),2)>=F_LOW) & (tmp(1:(idx-1),2)<=F_HIGH) & ismember(tmp(1:(idx-1),4),CHANNELS));
          data(i).MT_next=tmp(idx2,:);
          data(i).MT_next(:,1)=data(i).MT_next(:,1)-(chunk_curr-1)*CHUNK_TIME_WINDOWS(i);
          fseek(fid(i),-(size(tmp,1)-idx+1)*4*8,'cof');
          break;
        end
      end
    end

    sizeF=ceil(F_HIGH/df)-floor(F_LOW/df)+2*floor(maxNFFT/minNFFT/2)+1;
    sizeT=CHUNK_TIME_WINDOWS(1)+2*floor(maxNFFT/minNFFT/2)+1;
    im_next=false(sizeF,sizeT);

    for k=1:length(data)
      if(isempty(data(k).MT_next))  continue;  end
      tmpT=data(k).NFFT/minNFFT;
      tmpF=maxNFFT/data(k).NFFT;
      for i=(-floor(tmpF/2):floor(tmpF/2))+floor(maxNFFT/minNFFT/2)+1
        for n=(-floor(tmpT/2):floor(tmpT/2))+floor(maxNFFT/minNFFT/2)+1
          im_next(sub2ind([sizeF,sizeT],...
              round(data(k).MT_next(:,2)/df)+i-floor(F_LOW/df), ...
              tmpT*data(k).MT_next(:,1)+n))=true;
        end
      end
    end

    %convolve
    im_next=[zeros(sizeF,(CONV_SIZE(2)-1)/2) im_next zeros(sizeF,(CONV_SIZE(2)-1)/2)];
    im_next=logical(conv2(single(im_next),ones(CONV_SIZE),'same'));

    %segment
    syls_next=bwconncomp(im_next,8);
  else
    for i=1:length(data)
      data(i).MT_next=[];
    end
    im_next=[];
    syls_next=[];
  end

  if(exist('syls')==0)
    for i=1:length(data)
      data(i).MT=data(i).MT_next;
    end
    im=im_next;
    syls=syls_next;
    chunk_curr=chunk_curr+1;
    continue;
  end

  %unsplit across chunk boundaries
  flag=1;
  while(flag)
    flag=0;
    for i=1:syls.NumObjects
      [ri ci]=ind2sub(syls.ImageSize,syls.PixelIdxList{i});
      if(sum(ci>=(syls.ImageSize(2)-(CONV_SIZE(2)-1)/2))==0) continue;  end
      j=1;
      while j<=syls_next.NumObjects
        [rj cj]=ind2sub(syls_next.ImageSize,syls_next.PixelIdxList{j});
        if(sum(cj<=((CONV_SIZE(2)-1)/2))==0)  j=j+1;  continue;  end
        %if((max(ri) < (min(rj)-1)) || (max(rj) < (min(ri)-1)))  j=j+1;  continue;  end
        %cj=cj+chunk_splits(k+1)-chunk_splits(k);
        cj=cj+CHUNK_TIME_WINDOWS(1);
        min(min((repmat(ri,1,length(rj))-repmat(rj',length(ri),1)).^2 + ...
                (repmat(ci,1,length(cj))-repmat(cj',length(ci),1)).^2));
        if ans<=2
          %disp(['unsplitting syllable between chunks #' num2str(k) '-' num2str(k+1)]);
          flag=1;
          syls.PixelIdxList{i}=[syls.PixelIdxList{i}; ...
              syls_next.PixelIdxList{j}+CHUNK_TIME_WINDOWS(1)*syls.ImageSize(1)];
          syls_next.PixelIdxList(j)=[];
          syls_next.NumObjects=syls_next.NumObjects-1;
        else
          j=j+1;
        end
      end
    end
  end

  %throwout out small blobs
  syls2=regionprops(syls,'basic');
  tmp=find([syls2.Area]>OBJ_SIZE);
  syls2=syls2(tmp);
  syls.PixelIdxList=syls.PixelIdxList(tmp);
  syls.NumObjects=length(tmp);

  %calculate frequency contours
  freq_contour={};
  for i=1:length(syls2)
    tmp=[];
    for j=1:length(data)
      tmpT=data(j).NFFT/minNFFT;
%      idx=find(((tmpT*data(j).MT(:,1)+(CONV_SIZE(2)-1)/2-floor(tmpT/2))>=syls2(i).BoundingBox(1)) & ...
%               ((tmpT*data(j).MT(:,1)+(CONV_SIZE(2)-1)/2+floor(tmpT/2))<=sum(syls2(i).BoundingBox([1 3]))) & ...
%                (data(j).MT(:,2)>=(syls2(i).BoundingBox(2)*df+F_LOW)) & ...
%                (data(j).MT(:,2)<=(sum(syls2(i).BoundingBox([2 4]))*df+F_LOW)));
      foo=[tmpT*data(j).MT(:,1)+(CONV_SIZE(2)-1)/2 round(data(j).MT(:,2)/df)-floor(F_LOW/df)];
      [r c]=ind2sub(syls.ImageSize,syls.PixelIdxList{i});
      idx=ismember(foo,[c r],'rows');
      foo=data(j).MT(idx,1:3);
      foo(:,1)=foo(:,1)+(chunk_curr-2)*CHUNK_TIME_WINDOWS(j);  % +1?
      foo(:,1)=foo(:,1).*data(j).NFFT/2/FS;
      tmp=[tmp; foo];
    end
    tmp=sortrows(tmp);
    freq_contour{i}{1}=zeros(length(unique(tmp(:,1))),3);
    j=1;  l=1;
    while(j<=size(tmp,1))
      k=j+1;  while((k<=size(tmp,1)) && (tmp(j,1)==tmp(k,1)))  k=k+1;  end
      [~, idx]=max(tmp(j:(k-1),3));
      freq_contour{i}{1}(l,:)=tmp(j+idx-1,:);
      j=k;  l=l+1;
    end
  end

  %merge harmonically related syllables...
  if(MERGE_FREQ~=0)
    %disp('merge harmonically related syllables...');
    syls3=ones(1,length(syls2));
    for i=1:(length(syls2)-1)
      if(isempty(syls.PixelIdxList{i}))  continue;  end
      flag=1;
      while(flag)
        flag=0;
        for j=(i+1):length(syls2)
          if(isempty(syls.PixelIdxList{j}))  continue;  end
          doit=false;
          for k=1:length(freq_contour{i})
            [c,ii,jj]=intersect(freq_contour{i}{k}(:,1),freq_contour{j}{1}(:,1));
            if((length(c)/size(freq_contour{i}{k},1)<MERGE_FREQ_OVERLAP) && ...
               (length(c)/size(freq_contour{j}{1},1)<MERGE_FREQ_OVERLAP))
              continue;
            end
            doit=doit | ...
                sum(sum(abs((freq_contour{i}{k}(ii,2)./freq_contour{j}{1}(jj,2))*...
                    [1/3 1/2 2 3 2/3 3/2]-1)<MERGE_FREQ_RATIO)...
                >(MERGE_FREQ_FRACTION*length(c)));
          end
          if(doit)
            flag=1;
            syls.PixelIdxList{i}=[syls.PixelIdxList{i}; syls.PixelIdxList{j}];
            syls.PixelIdxList{j}=[];
            syls2(i).BoundingBox(1)=...
                min([syls2(i).BoundingBox(1) syls2(j).BoundingBox(1)]);
            syls2(i).BoundingBox(2)=...
                min([syls2(i).BoundingBox(2) syls2(j).BoundingBox(2)]);
            syls2(i).BoundingBox(3)=...
                max([sum(syls2(i).BoundingBox([1 3])) sum(syls2(j).BoundingBox([1 3]))])-...
                syls2(i).BoundingBox(1);
            syls2(i).BoundingBox(4)=...
                max([sum(syls2(i).BoundingBox([2 4])) sum(syls2(j).BoundingBox([2 4]))])-...
                syls2(i).BoundingBox(2);
            syls3(i)=syls3(i)+syls3(j);
            syls3(j)=0;
            freq_contour{i}={freq_contour{i}{:} freq_contour{j}{:}};
            freq_contour{j}=[];
          end
        end
      end
    end
    idx=find(syls3>=1);
    syls.NumObjects=length(idx);
    syls.PixelIdxList={syls.PixelIdxList{idx}};
    syls2=regionprops(syls,'basic');
    freq_contour={freq_contour{idx}};
  end

  %merge temporally nearby syllables...
  if(MERGE_TIME~=0)
    %disp('merge temporally nearby syllables...');
    syls3=ones(1,length(syls2));
    for i=1:(length(syls2)-1)
      if(isempty(syls.PixelIdxList{i}))  continue;  end
      flag=1;
      while(flag)
        flag=0;
        for j=(i+1):length(syls2)
          if(isempty(syls.PixelIdxList{j}))  continue;  end
          if(((sum(syls2(i).BoundingBox([1 3]))+MERGE_TIME) > syls2(j).BoundingBox(1)) &&...
             ((sum(syls2(j).BoundingBox([1 3]))+MERGE_TIME) > syls2(i).BoundingBox(1)))
            flag=1;
            syls.PixelIdxList{i}=[syls.PixelIdxList{i}; syls.PixelIdxList{j}];
            syls.PixelIdxList{j}=[];
            syls2(i).BoundingBox(1)=...
                min([syls2(i).BoundingBox(1) syls2(j).BoundingBox(1)]);
            syls2(i).BoundingBox(2)=...
                min([syls2(i).BoundingBox(2) syls2(j).BoundingBox(2)]);
            syls2(i).BoundingBox(3)=...
                max([sum(syls2(i).BoundingBox([1 3])) sum(syls2(j).BoundingBox([1 3]))])-...
                syls2(i).BoundingBox(1);
            syls2(i).BoundingBox(4)=...
                max([sum(syls2(i).BoundingBox([2 4])) sum(syls2(j).BoundingBox([2 4]))])-...
                syls2(i).BoundingBox(2);
            syls3(i)=syls3(i)+syls3(j);
            syls3(j)=0;
            freq_contour{i}={freq_contour{i}{:} freq_contour{j}{:}};
            freq_contour{j}=[];
          end
        end
      end
    end
    idx=find(syls3>=NSEG);
    syls.NumObjects=length(idx);
    syls.PixelIdxList={syls.PixelIdxList{idx}};
    syls2=regionprops(syls,'basic');
    freq_contour={freq_contour{idx}};
  end

  %cull short syllables...
  if(MIN_LENGTH>0)
    disp('cull short syllables...');
    reshape([syls2.BoundingBox],4,length(syls2))';
    idx=find(((ans(:,3)-CONV_SIZE(2)+1)*minNFFT/2/FS)>MIN_LENGTH);
    syls.NumObjects=length(idx);
    syls.PixelIdxList={syls.PixelIdxList{idx}};
    syls2=regionprops(syls,'basic');
    freq_contour={freq_contour{idx}};
  end

  tmp=reshape([syls2.BoundingBox],4,length(syls2))';
  %%tmp(:,1)=tmp(:,1)-(CONV_SIZE(2)-1)/2+(CONV_SIZE(2)-1)/2;
  tmp(:,3)=tmp(:,3)-CONV_SIZE(2)+1;
  skytruth=[skytruth; ...
      ([tmp(:,1) tmp(:,1)+tmp(:,3)]+(chunk_curr-2)*CHUNK_TIME_WINDOWS(1))*minNFFT/2/FS ...
      zeros(size(tmp,1),1) ...
      [tmp(:,2) tmp(:,2)+tmp(:,4)].*df+F_LOW];
  freqtruth={freqtruth{:} freq_contour{:}};

  %compare to ground truth
  if(GROUNDTRUTH)
    while((sidx<=size(skytruth,1))&&(skytruth(sidx,2)<groundtruth(gidx,1)))
      sidx=sidx+1;
    end
    while((sidx<=size(skytruth,1)) && (gidx<=size(groundtruth,1)))
      if(skytruth(sidx,1)<groundtruth(gidx,2))
        groundtruth(gidx,3)=sidx;
        skytruth(sidx,3)=gidx;
        sidx=sidx+1;
      end
      if(sidx>size(skytruth,1))  break;  end
      if(skytruth(sidx,1)>groundtruth(gidx,2))
        gidx=gidx+1;
        if(gidx>size(groundtruth,1))  break;  end
      end
      while((sidx<size(skytruth,1))&&(skytruth(sidx,2)<groundtruth(gidx,1)))
        sidx=sidx+1;
      end
    end
    if ~eof
      misses=find(groundtruth(1:min([gidx-1 size(groundtruth,1)]),3)==0);
      false_alarms=find(skytruth(:,3)==0);
      hits=setdiff(1:min([gidx-1 size(groundtruth,1)]),misses);
    else
      misses=find(groundtruth(1:size(groundtruth,1),3)==0);
      false_alarms=find(skytruth(:,3)==0);
      hits=setdiff(1:size(groundtruth,1),misses);
    end
  end

  %plot
  if(SAVE_WAV || SAVE_PNG)
    clf;  hold on;

    [r,c]=ind2sub(syls.ImageSize,cat(1,syls.PixelIdxList{:}));
    c=c-(CONV_SIZE(2)-1)/2+(chunk_curr-2)*CHUNK_TIME_WINDOWS(1);
    plot(c.*(minNFFT/2)./FS,r.*df+F_LOW,'kx');

    for i=1:length(syls2)
      for j=1:length(freqtruth{end-i+1})
        plot(freqtruth{end-i+1}{j}(:,1),freqtruth{end-i+1}{j}(:,2),'r-');
      end
    end

    if(GROUNDTRUTH)
      left =(chunk_curr-2)*CHUNK_TIME_WINDOWS(end)*maxNFFT/2/FS;
      right=(chunk_curr-1)*CHUNK_TIME_WINDOWS(end)*maxNFFT/2/FS;
      idx=find(((groundtruth(:,1)>=left) & (groundtruth(:,1)<=right)) | ...
               ((groundtruth(:,2)>=left) & (groundtruth(:,2)<=right)));
      if(~isempty(idx))
        line(groundtruth(idx,[1 2 2 1 1]),...
            [F_LOW F_LOW F_HIGH F_HIGH F_LOW],'color',[0 1 0]);
      end
    end

    plot(skytruth((end-length(syls2)+1):end,[1 2 2 1 1])',...
         skytruth((end-length(syls2)+1):end,[4 4 5 5 4])','y');

    %plot(repmat(chunk_splits*minNFFT/2/FS,2,1),...
    %     repmat([F_LOW; F_HIGH],1,length(chunk_splits)),'c');

    axis tight;
    v=axis;  axis([v(1) v(2) F_LOW F_HIGH]);
    xlabel('time (s)');
    ylabel('frequency (Hz)');

    [b,a]=butter(4,F_LOW/(FS/2),'high');

    % plot hits, misses and false alarms separately
    if(~GROUNDTRUTH)
      while voc_num<=min([200 size(skytruth,1)])
        left=skytruth(voc_num,1);
        right=skytruth(voc_num,2);
        ax2_print(voc_num,left,right,'voc',filename,FS,minNFFT,SAVE_WAV,SAVE_PNG,b,a,CHANNELS);
        voc_num=voc_num+1;
      end
    else
      while hit_num<=min([20 length(hits)])
        left =min([groundtruth(hits(hit_num),1) skytruth(groundtruth(hits(hit_num),3),1)]);
        right=max([groundtruth(hits(hit_num),2) skytruth(groundtruth(hits(hit_num),3),2)]);
        ax2_print(hit_num,left,right,'hit',filename,FS,minNFFT,SAVE_WAV,SAVE_PNG,b,a,CHANNELS);
        hit_num=hit_num+1;
      end

      while miss_num<=min([100 size(misses,1)])
        left=groundtruth(misses(miss_num),1);
        right=groundtruth(misses(miss_num),2);
        ax2_print(miss_num,left,right,'miss',filename,FS,minNFFT,SAVE_WAV,SAVE_PNG,b,a,CHANNELS);
        miss_num=miss_num+1;
      end

      while fa_num<=min([100 size(false_alarms,1)])
        left=skytruth(false_alarms(fa_num),1);
        right=skytruth(false_alarms(fa_num),2);
        ax2_print(fa_num,left,right,'false_alarm',filename,FS,minNFFT,SAVE_WAV,SAVE_PNG,b,a,CHANNELS);
        fa_num=fa_num+1;
      end
    end
  end

  for i=1:length(data)
    data(i).MT=data(i).MT_next;
  end
  im=im_next;
  syls=syls_next;
  chunk_curr=chunk_curr+1;
end

%dump files
if(GROUNDTRUTH)
  disp([num2str(num) ': ' num2str(size(groundtruth,1)) ' manually segmented syllables, ' num2str(length(misses)) ...
      ' (' num2str(100*length(misses)/size(groundtruth,1),3) '%) of which are missed']);

  disp([num2str(num) ': ' num2str(size(skytruth,1)) ' automatically segmented syllables, ' num2str(length(false_alarms)) ...
      ' (' num2str(100*length(false_alarms)/size(skytruth,1),3) '%) of which are false alarms']);
else
  disp([num2str(num) ': ' num2str(size(skytruth,1)) ' automatically segmented syllables']);
end

tmp=[skytruth(:,1:2) skytruth(:,4:5)];
save([filename '.voc' sprintf('%d',CHANNELS)],'tmp','-ascii');
save([filename '.fc' sprintf('%d',CHANNELS)],'freqtruth');
if(GROUNDTRUTH)
  tmp=groundtruth(misses,1:2);
  save([filename '.miss' sprintf('%d',CHANNELS)],'tmp','-ascii');
  tmp=[skytruth(false_alarms,1:2) skytruth(false_alarms,4:5)];
  save([filename '.fa' sprintf('%d',CHANNELS)],'tmp','-ascii');
end

varname=@(x) inputname(1);
fid=fopen([filename '.params' sprintf('%d',CHANNELS)],'w');
for i=1:length(data)
  jj=fieldnames(data(i));
  for j=1:length(jj)-2
    fprintf(fid,'%s=%g;\n',char(jj(j)),data(i).(char(jj(j))));
  end
  fprintf(fid,'\n');
end
fprintf(fid,'%s=%g;\n',varname(OBJ_SIZE),OBJ_SIZE);
fprintf(fid,'%s=[%g %g];\n',varname(CONV_SIZE),CONV_SIZE);
fprintf(fid,'%s=%g;\n',varname(F_LOW),F_LOW);
fprintf(fid,'%s=%g;\n',varname(F_HIGH),F_HIGH);
fprintf(fid,'%s=%g;\n',varname(NSEG),NSEG);
fprintf(fid,'%s=[%g];\n',varname(MERGE_TIME),MERGE_TIME);
fprintf(fid,'%s=%g;\n',varname(MERGE_FREQ),MERGE_FREQ);
fprintf(fid,'%s=%g;\n',varname(MERGE_FREQ_OVERLAP),MERGE_FREQ_OVERLAP);
fprintf(fid,'%s=%g;\n',varname(MERGE_FREQ_RATIO),MERGE_FREQ_RATIO);
fprintf(fid,'%s=%g;\n',varname(MERGE_FREQ_FRACTION),MERGE_FREQ_FRACTION);
fprintf(fid,'%s=[%s];\n',varname(CHANNELS),num2str(CHANNELS));
fclose(fid);



function ax2_print(i,left,right,type,filename,FS,NFFT,SAVE_WAV,SAVE_PNG,b,a,CHANNELS)

tmp=[];  p=[];
for j=CHANNELS
  fid=fopen([filename '.ch' num2str(j)],'r');
  if(fid<0)  continue;  end
  fseek(fid,round(4*(round((left-0.025)*FS))),-1);
  tmp=fread(fid,round((right-left+0.050)*FS),'float32');
  fclose(fid);
  if(SAVE_WAV)
    tmp2=filtfilt(b,a,tmp);
    tmp2=tmp2./max([max(tmp2)-min(tmp2)]);
    wavwrite(tmp2,22000,[fileparts(filename) '/' type num2str(i) '.ch' num2str(j) '.wav']);
  end
  [s,f,t,p(j,:,:)]=spectrogram(tmp,NFFT,[],[],FS,'yaxis');
end
tmp=squeeze(max(p,[],1));
tmp=log10(abs(tmp));
tmp4=reshape(tmp,1,prod(size(tmp)));
tmp2=prctile(tmp4,1);
tmp3=prctile(tmp4,99);
idx=find(tmp<tmp2);  tmp(idx)=tmp2;
idx=find(tmp>tmp3);  tmp(idx)=tmp3;
h=surf(t+left-0.025,f-f(2)/2,tmp,'EdgeColor','none');
uistack(h,'bottom');
colormap(gray);
axis tight;
set(gca,'xlim',[left right]+[-0.025 0.025]);
title([type ' #' num2str(i)]);
drawnow;
if(SAVE_PNG)  print('-dpng',[fileparts(filename) '/' type num2str(i) '.png']);  end
delete(h);