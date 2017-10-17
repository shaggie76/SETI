@echo off
wget --quiet -O host.gz http://setiathome.berkeley.edu/stats/host.gz
scanHosts.pl > GPUs.csv
aggregateGPUs.pl -max=500
aggregateOutput.pl | tee Results.csv
