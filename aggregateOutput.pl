#!/usr/bin/perl

use strict;
use warnings;

my $MIN_WORK_UNITS = 25;
my $MIN_HOST_IDS = 10;

my %hardwareStats; # gpu -> { tdp => ..., gf => ... };

my %API_PRETTY = ( 'opencl' => 'OpenCL', 'cuda' => 'CUDA' );
my @SORTED_API = ( 'OpenCL', 'CUDA' );

my @TELESCOPES = ( 'All', 'Arecibo', 'Greenbank' );

my $fd;
open($fd, "HardwareStats.csv") or die;

while(<$fd>)
{
    chomp;
    my @col = split(/,/, $_);

    if(scalar(@col) != 3)
    {
        print("Parse error: HardwareStats.csv $_\n");
        next;
    }

    if($col[0] eq "GPU")
    {
        next;
    }

    my $gpu = $col[0];
    my $tdp = $col[1];
    my $gf = $col[2];

    $hardwareStats{$gpu} = { tdp => $tdp, gf => $gf };
}

close($fd);

my %gpuToStats; # gpu -> api -> hostId -> resultId -> { csv fields }

foreach my $outputDir (sort(glob("Output-*")))
{
    foreach my $file (sort(glob("$outputDir/*.csv")))
    {
        my $fd;
        open($fd, $file) or die;

        while(<$fd>)
        {
            my @col = split(/, /, $_);

            if(scalar(@col) != 9)
            {
                print("Parse error: $file $_");
                next;
            }

            if($col[0] eq "HostID")
            {
                next;
            }

            my $hostId = int($col[0]);
            my $resultId = int($col[1]);
            my $taskName = $col[2];

            my $gpu = $col[3];
            my $api = $col[4];

            my $credit = $col[5];
            my $runTime = $col[6];
            my $cpuTime = $col[7];
            my $gpuConcurrency = int($col[8]);

            if(($gpu =~ /^\[\d\]/) && ($gpu =~ /\&/))
            {
                next; # Omit multi-GPU
            }

            # Clean up some stuff missed by scanHosts.pl 
            $gpu =~ s/Intel Intel/Intel/i;
            $gpu =~ s/\bIntel\b/INTEL/i;
            $gpu =~ s/AMD ATI\b/AMD/i;
            $gpu =~ s/^GeForce\b/NVIDIA GeForce/i;
            $gpu =~ s/\(R\)//gi;
            $gpu =~ s/\(TM\)//gi;
            $gpu =~ s/\s\s/ /g;

            if(defined($API_PRETTY{lc($api)}))
            {
                $api = $API_PRETTY{lc($api)};
            }
            else
            {
                next;
            }

            my $cph = $gpuConcurrency * (60 * 60 * $credit) / $runTime;

            # Note this nicely eliminates duplicate results
            $gpuToStats{$gpu}{$api}{$hostId}{$resultId} =
            {
                hostId => $hostId,
                taskName => $taskName,
                credit => $credit,
                runTime => $runTime,
                cpuTime => $cpuTime,
                gpuConcurrency => $gpuConcurrency,
                cph => $cph
            };
        }

        close($fd);
    }
}

foreach my $gpu (keys %gpuToStats)
{
    foreach my $api (keys %{$gpuToStats{$gpu}})
    {
        foreach my $hostId (keys %{$gpuToStats{$gpu}{$api}})
        {
            if(scalar(keys %{$gpuToStats{$gpu}{$api}{$hostId}}) < $MIN_WORK_UNITS)
            {
                delete $gpuToStats{$gpu}{$api}{$hostId};
            }
        }

        if(scalar(keys %{$gpuToStats{$gpu}{$api}}) < $MIN_HOST_IDS)
        {
            delete $gpuToStats{$gpu}{$api};
        }
    }

    unless(keys %{$gpuToStats{$gpu}})
    {
        delete $gpuToStats{$gpu};
    }
}

sub aggregateResults($@)
{
    my $tdp = shift;
    my $n = scalar(@_);

    unless($n)
    {
        return undef;
    }

    # Winsorize the middle 60% -- larger windows tend to include too many outliers
    my $minIndex = int(($n * 0.2) + 0.5);
    my $maxIndex = int(($n * 0.8) + 0.5);

    my $sum = 0;
    my $sum2 = 0;

    my %hosts;

    foreach (@_)
    {
        $hosts{$_->{'hostId'}} = 1;

        my $cph = $_->{'cph'};
        $sum += $cph;
        $sum2 += $cph * $cph;
    }

    my $avgCPH = $sum / $n;
    my $devCPH = sqrt(($sum2 / $n) - ($avgCPH * $avgCPH));

    return
    {
        'tasks' => $n,
        'hosts' => scalar(keys(%hosts)),

        'minCPH' => $_[$minIndex]->{"cph"},
        'maxCPH' => $_[$maxIndex]->{"cph"},
        'dltCPH' => $_[$maxIndex]->{"cph"} - $_[$minIndex]->{"cph"},
        'medCPH' => $_[int(($n * 0.5) + 0.5)]->{"cph"},

        'minCPWH' => $_[$minIndex]->{"cph"} / $tdp,
        'maxCPWH' => $_[$maxIndex]->{"cph"} / $tdp,
        'dltCPWH' => $_[$maxIndex]->{"cph"} / $tdp - $_[$minIndex]->{"cph"} / $tdp,
        'medCPWH' => $_[int(($n * 0.5) + 0.5)]->{"cph"} / $tdp,

        'avgCPH' => $avgCPH,
        'devCPH' => $devCPH
    };
}

sub getAverageCpuLoad(@)
{
    my $totalRunTime = 0;
    my $totalCpuTime = 0;

    foreach (@_)
    {
        $totalRunTime += $_->{'runTime'};
        $totalCpuTime += $_->{'cpuTime'};
    }

    return $totalCpuTime / $totalRunTime;
}

my %gpuToResults;
my %gpuToCpuLoad;

foreach my $gpu (keys %gpuToStats)
{
    unless(defined($hardwareStats{$gpu}{'tdp'}))
    {
        print("No TDP for $gpu\n");
        next;
    }

    my $tdp = $hardwareStats{$gpu}{'tdp'};

    my $bestAPI;
    my $bestCPH = -1;

    my %apiToResults; # api -> { all | greenbank | arecibo } => { median, min, max, crwh }

    foreach my $api (keys %{$gpuToStats{$gpu}})
    {
        my @results = ();

        foreach my $hostId (keys %{$gpuToStats{$gpu}{$api}})
        {
            push(@results, values(%{$gpuToStats{$gpu}{$api}{$hostId}}));
        }

        @results = sort { $a->{"cph"} <=> $b->{"cph"} } @results;

        $apiToResults{$api}{'All'} = aggregateResults($tdp, @results);

        if($apiToResults{$api}{'All'}{'medCPH'} > $bestCPH)
        {
            $bestCPH = $apiToResults{$api}{'All'}{'medCPH'};
            $bestAPI = $api;
        }

        $gpuToCpuLoad{$gpu}{$api} = getAverageCpuLoad(@results);
        
        # Arecibo: 17my10ab.26379.19699.15.42.58.vlar_2 
        # Greenbank: blc2_2bit_guppi_57403_68833_HIP11048_OFF_0003.27930.831.21.44.85.vlar_1
        my @arecibo = ();
        my @greenbank = ();

        foreach (@results)
        {
            if($_->{'taskName'} =~ /^blc/i)
            {
                push(@greenbank, $_);
            }
            else
            {
                push(@arecibo, $_);
            }
        }

        $apiToResults{$api}{'Greenbank'} = aggregateResults($tdp, @greenbank);
        $apiToResults{$api}{'Arecibo'} = aggregateResults($tdp, @arecibo);
    }

    $gpuToResults{"$gpu ($bestAPI)"} = $apiToResults{$bestAPI};
}

my @sortedGPUs = sort { $gpuToResults{$a}{'All'}{'medCPH'} <=> $gpuToResults{$b}{'All'}{'medCPH'} } keys(%gpuToResults);

my @CSV_FIELDS = ( 'hosts', 'tasks', 'avgCPH', 'devCPH', 'medCPH', 'maxCPH', 'minCPH', 'dltCPH', 'medCPWH', 'maxCPWH', 'minCPWH', 'dltCPWH' );

foreach my $telescope (@TELESCOPES)
{
    print("GPU ($telescope), Hosts, Tasks, CPH Average, CPH StdDev, CPH Median, CPH Max, CPH Min, CPH Delta, CPWH Median, CPWH Max, CPWH Min, CPWH Delta\n");

    foreach my $gpu (@sortedGPUs)
    {
        print("$gpu, ");

        my $results = $gpuToResults{$gpu}{$telescope};
        my @fields = @{$results}{@CSV_FIELDS};

        print(join(", ", @fields));
        print("\n");
    }

    print("\n");
}

print("GPU, " . join(", ", @SORTED_API) . "\n");

foreach my $gpuEx (@sortedGPUs)
{
    my $gpu = $gpuEx;
    $gpu =~ s/ \(.*//;
    
    print("$gpu");

    foreach my $api (@SORTED_API)
    {
        print(", ");

        if(defined($gpuToCpuLoad{$gpu}{$api}))
        {
            print($gpuToCpuLoad{$gpu}{$api});
        }
    }

    print("\n");
}
