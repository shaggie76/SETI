## aggregate.pl

A script for aggregating credit/hour averages for SETI@home hosts with the 
goal of estimating credit/watt.

I opted for expecting the curl command-line program to be installed rather
than a PERL module because none of the modules I checked were installed by
default.

It works by scrolling through 5 pages of verified results for a given
host and works out the average credit to run-time ratio.

```aggregate.pl 8026559  
Host, Device, Credit/Hour, Work Units  
8026559, Core i7-5960X @ 3.00GHz, 751.646218607873, 47  
8026559, GeForce GTX 980 Ti, 680.596911595191, 53
```

## scanHosts.pl

Takes a SETI@Home host dump and extracts a list of gpus by host-id that have
been updated recently and have enough total credit.

```wget https://setiathome.berkeley.edu/stats/hosts.gz  
scanHosts.pl > GPUs.csv ```

## aggregateGPUs.pl

Scans GPUs.csv for large enough groups of results for specific models and
then grinds them through aggregate.pl and writes the results to Output dir

## aggregateOutput.pl

Analyzes the data in the output dir to take the highest results for each
GPU to try to eliminate stats for people running multiple work-units at
the same time. Generates a spreadsheet output.

