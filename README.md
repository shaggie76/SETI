## Synopsis

A script for aggregating credit/hour averages for SETI@home hosts with the 
goal of estimating credit/watt.

I opted for expecting the curl command-line program to be installed rather
than a PERL module because none of the modules I checked were installed by
default.

It works by scrolling through 5 pages of verified results for a given
host and works out the average credit to run-time ratio.

## Example

aggregate.pl 8026559

cpu average 44.2880656913519 CR/h (52 results)
gpu average 692.155971167249 CR/h (48 results)

CPU results are per-thread so multiply your CR/hr by your active threads to
get an approximate CR/h for the whole CPU. In this case the CPU is a 16-thread
machine so it might be around 708.6 CR/hr if fully employed (I'm not sure 
about how the GPU-reservation works though).

I don't have a multi-GPU setup but judging from other people's stats it looks
like it issues one task spread across all GPUs.

In the PC above it's about 250W for the CPU and 250W for the GPU (my UPS says
it's drawing about 500W total and the TDP for the 980Ti should be 250W). This
gives me the following estimates:

CPU 708.6 CR/H / 250W = 2.83 CR/Wh
GPU 692 CR/H / 250W = 2.77 CR/Wh

