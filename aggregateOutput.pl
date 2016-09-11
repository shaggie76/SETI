use strict;
use warnings;

use Sort::Naturally;

my $MIN_WORK_UNITS = 10;
my $MIN_HOST_IDS = 10;

my %gpuToStats; # gpu -> api -> hid -> { h => ..., c => ... , w => ... }
my %hardwareStats; # gpu -> { tdp => ..., gf => ... };

my %API_PRETTY = ( 'opencl' => 'OpenCL' );
#my %API_PRETTY = ( 'opencl' => 'OpenCL', 'cuda' => 'CUDA' );
my @SORTED_APIS = reverse sort values(%API_PRETTY);

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

my @files = sort(glob("Output/*.csv"));

foreach my $file (@files)
{
    my $fd;

    open($fd, $file) or die;

    while(<$fd>)
    {
        my @col = split(/, /, $_);

        if(scalar(@col) != 7)
        {
            print("Parse error: $file $_\n");
            next;
        }

        if($col[0] eq "Host")
        {
            next;
        }

        my $hid = int($col[0]);
        my $api = $col[1];
        my $gpu = $col[2];
        my $credit = 0+$col[3];
        my $seconds = 0+$col[4];
        my $creditPerHour = 0+$col[5];
        my $workUnits = int($col[6]);

        if($workUnits < $MIN_WORK_UNITS)
        {
            next;
        }

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
        $gpu =~ s/GeForce GTX 1060 6GB/GeForce GTX 1060/;

        if(defined($API_PRETTY{lc($api)}))
        {
            $api = $API_PRETTY{lc($api)};
        }
        else
        {
            next;
        }

        if
        (
            !defined($gpuToStats{$gpu}{$api}{$hid}) ||
            ($gpuToStats{$gpu}{$api}{$hid}{"w"} <= $workUnits)
        )
        {
            $gpuToStats{$gpu}{$api}{$hid} =
            {
               h => $hid,
               c => $credit,
               s => $seconds,
               cph => $creditPerHour,
               w => $workUnits
            };
        }
    }

    close($fd);
}

# Cull thing without enough hosts
foreach my $gpu (nsort(keys %gpuToStats))
{
    foreach my $api (sort(keys %{$gpuToStats{$gpu}}))
    {
        if(scalar(keys $gpuToStats{$gpu}{$api}) < $MIN_HOST_IDS)
        {
            delete $gpuToStats{$gpu}{$api};
        }
    }

    if(!scalar(keys $gpuToStats{$gpu}))
    {
        delete $gpuToStats{$gpu};
    }
}

my %cphStats; # api->gpu->{ avg, stddev, values }

foreach my $gpu (keys %gpuToStats)
{
    foreach my $api (@SORTED_APIS)
    {
        unless(defined($gpuToStats{$gpu}{$api}))
        {
            next;
        }
        
        # Convert to array we can sort
        my @results;

        foreach my $hid (keys $gpuToStats{$gpu}{$api})
        {
            push(@results, $gpuToStats{$gpu}{$api}{$hid});
        }

        my $n = scalar(@results);

        if($n < $MIN_HOST_IDS)
        {
            next;
        }

        @results = sort { $a->{"cph"} <=> $b->{"cph"} } @results;

        my $tdp = $hardwareStats{$gpu}{tdp};

        # Winsorize the middle 60% -- larger windows tend to include too many outliers
        my $minIndex = int(($n * 0.2) + 0.5);
        my $maxIndex = int(($n * 0.8) + 0.5);
        my $minValue = $results[$minIndex]->{"cph"};
        my $maxValue = $results[$maxIndex]->{"cph"};
        my $median = $results[int(($n * 0.5) + 0.5)]->{"cph"};
        my $medPwr = $median / $tdp;

        $cphStats{$api}{$gpu}{'min'} = $minValue;
        $cphStats{$api}{$gpu}{'max'} = $maxValue;
        $cphStats{$api}{$gpu}{'med'} = $median;
        $cphStats{$api}{$gpu}{'medPwr'} = $medPwr;
        $cphStats{$api}{$gpu}{'n'} = $maxIndex - $minIndex;
    }
}

foreach my $api (@SORTED_APIS)
{
    unless(defined($cphStats{$api}))
    {
        next;
    }

    print("Credit/Hour ($api)\n\n");

    my @gpus = sort { $cphStats{$api}{$a}{'med'} <=> $cphStats{$api}{$b}{'med'} } keys($cphStats{$api});

    print("GPU,Min CPH,CPH Spread,Hosts\n");

    foreach my $gpu (@gpus)
    {
        my $minValue = $cphStats{$api}{$gpu}{'min'};
        my $maxValue = $cphStats{$api}{$gpu}{'max'};
        my $spread = $maxValue - $minValue;
        my $n = $cphStats{$api}{$gpu}{'n'};
        print("$gpu,$minValue,$spread,$n\n");
    }

    print("\n");
}

foreach my $api (@SORTED_APIS)
{
    unless(defined($cphStats{$api}))
    {
        next;
    }

    print("Credit/Watt-Hour ($api)\n\n");

    my @gpus = sort { $cphStats{$api}{$a}{'medPwr'} <=> $cphStats{$api}{$b}{'medPwr'} } keys($cphStats{$api});

    print("GPU,Min CPH/WH,CPH/WH Spread\n");

    foreach my $gpu (@gpus)
    {
        my $tdp = $hardwareStats{$gpu}{tdp};

        my $minValue = $cphStats{$api}{$gpu}{'min'} / $tdp;
        my $maxValue = $cphStats{$api}{$gpu}{'max'} / $tdp;
        my $spread = $maxValue - $minValue;
        my $n = $cphStats{$api}{$gpu}{'n'};
        print("$gpu,$minValue,$spread,$n\n");
    }

    print("\n");
}

