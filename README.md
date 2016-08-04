### aggregate.pl

This script aggregates credit and time for tasks for SETI@home hosts.

I opted for expecting the curl command-line program to be installed rather than a PERL module because none of the modules I checked were installed by default.

It works by scrolling through the pages of verified results on the website for the given
host and generates statistics. You can pass multiple hosts at once.

```
aggregate.pl [-cpu | -gpu] [-anon] [-v] [-max=n] <host id> [host id...]
```
* Use -cpu or -gpu to specify one or the other (the default is to include both).
* Use -anon if you want the anonymous platform (the default is to only collect stock).
* Use -v to print verbose data as it scans.
* Use -max=n to stop after enough valid hosts are found.

Example output:
```
Host, API, Device, Credit, Seconds, Credit/Hour, Work Units
8026559, cpu, Intel Core i7-5960X @ 3.00GHz, 8596.25, 42917.938125, 721.062132804871, 107
8026559, opencl, NVIDIA GeForce GTX 980 Ti, 7727.68, 43382.76, 641.260445393516, 93
```
**NOTE 1**: currently the cpu rate is automatically multiplied by the number of processors -- this is not ideal but is a fair approximation. GPU data, on the other hand, is not multiplied because we currently cannot know how many tasks are being being run at once.

**NOTE 2**: the GUPPI Rescheduler will completely invalidate the CPU/GPU breakdown because the server has no idea that you've subcontracted a task to a different type of processor.

### scanHosts.pl

Takes a SETI@Home host dump and extracts the set of gpus by host-id that have
been updated recently and have enough total credit. You'll need to get a copy of the hosts database first:

```
wget https://setiathome.berkeley.edu/stats/hosts.gz  
scanHosts.pl > GPUs.csv
```

### aggregateGPUs.pl

Once you have `GPUs.csv` this script script randomly shuffles the hosts for each GPU and calls aggregate.pl for a small subset of them; it appends the results to a CSV in the Output folder named for each model. 

Note that if you re-run the aggregate without clearing the results folder first it will only scan hosts that it has not previsouly scanned. 

### aggregateOutput.pl

When you have enough results for each card you use this script to combine and average them for each card. The mean is winsorized to to omit the bottom half or 3/4 of the host results -- the idea here is to try to ignore hosts that may be running multiple tasks concurrently (this will manifest as lower throughput per task).


