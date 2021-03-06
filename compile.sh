#!/bin/bash

#ssh login
#qlogin -l interactive=true,matlab=1
#cd to ax/
#./compile.sh

#hard-coded for matlab 2014a on janelia cluster

git log -1 --pretty=format:"%ci %H" > version.txt

mkdir -p ax1

/usr/local/matlab-2014a/bin/mcc -o ax1 \
  -W main:ax1 \
  -T link:exe \
  -d ax1 \
  -w enable:specified_file_mismatch \
  -w enable:repeated_file \
  -w enable:switch_ignored \
  -w enable:missing_lib_sentinel \
  -w enable:demo_license \
  -v ax1.m \
  -a version.txt  # -a /full/path/to/omnivore/binread.m

mkdir -p ax2

/usr/local/matlab-2014a/bin/mcc -o ax2 \
  -R -singleCompThread \
  -W main:ax2 \
  -T link:exe \
  -d ax2 \
  -w enable:specified_file_mismatch \
  -w enable:repeated_file \
  -w enable:switch_ignored \
  -w enable:missing_lib_sentinel \
  -w enable:demo_license \
  -v ax2.m \
  -a version.txt
