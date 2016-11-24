@echo off
wget -O host.gz http://setiathome.berkeley.edu/stats/host.gz
scanHosts.pl > GPUs.csv
aggregateGPUs.pl
aggregateGPUs.pl -rescan
aggregateOutput.pl
