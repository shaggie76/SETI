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
* Use -csv to print verbose data in comma-separated value format.
* Use -max=n to stop after enough valid hosts are found.

Example output:
```
aggregate.pl -gpu 8026559

Host: 8026559 (2 GPU Tasks / Card)

[2] NVIDIA GeForce GTX 980 Ti (OpenCL)
     924 Credit / Hour / Card
    1847 Credit / Hour / 2 Cards
     95% Core / Task
     502 Tasks
```
**NOTE 1**: currently the cpu rate is automatically multiplied by the number of processors less the theoretical CPU footprint for the GPU tasks -- this isn't great because we may think you only need 1.5 cores for GPU tasks but you may have configured it to reserve a whole core regardless of whether it needs it. Furthermore it depends on the "-instances_per_device" multibeam command-line to give us output to detect people running multiple hosts (this option doesn't seem to be supported on all platforms yet and it may not even be required so I don't see it used much).

**NOTE 2**: the GUPPI Rescheduler will completely invalidate the CPU/GPU breakdown because the server has no idea that you've subcontracted a task to a different type of processor.

### scanHosts.pl

Takes a SETI@Home host dump and extracts the set of gpus by host-id that have
been updated recently and have enough total credit. You'll need to get a copy of the hosts database first:

```
wget http://setiathome.berkeley.edu/stats/host.gz  
scanHosts.pl > GPUs.csv
```

### aggregateGPUs.pl

Once you have `GPUs.csv` this script script randomly shuffles the hosts for each GPU and calls aggregate.pl for a small subset of them; it appends the results to a CSV in the output folder named for each model. 

It names the output folder with the date-stamp of the hosts.gz file; it also handles incremental output so that if you cancel and restart it should resume on the card it was scanning. 

If you re-run he script after fetching a new hosts.gz it will use a new output folder and start over -- the idea is generally I get a new hosts.gz every few weeks and generate graphs for the forums.

If you wan to improve resolution for a scan you can re-run it with the -rescan command-line argument; this will do a full scan but will only includes hosts that it has not previously scanned in that hosts.gz.

### aggregateOutput.pl

When you have enough results for each card you use this script to combine and them for each card. The data is scanned for the middle 60% of hosts, sorted by median, and emitted with min & range for easy floating bar graphing in Excel -- the idea here is to try to ignore hosts that may be running multiple tasks concurrently (this will manifest as lower throughput per task). Looking at scatter plots this seems to remove the outliers very well and still leave a very thick set of data that is evenly clustered between the bounds identified.

The default is to print the CSV to shell so pipe it to a CSV of your choice:

```
aggregateOutput.pl > Results.csv
start Results.csv
````

And then graph your spreadsheet however you like! 
