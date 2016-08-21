use strict;
use warnings;

use Sort::Naturally;

my $MIN_WORK_UNITS = 10;
my $MIN_HOST_IDS = 10;

my %gpuToStats; # gpu -> api -> hid -> { h => ..., c => ... , w => ... }
my %hardwareStats; # gpu -> { tdp => ..., gf => ... };

my %API_PRETTY = ( 'opencl' => 'OpenCL', 'cuda' => 'CUDA' );
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

        if($gpu =~ /^\[\d\]/)
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

my %gpuToAvg;

print("GPU");
foreach my $api (@SORTED_APIS)
{
    print(",Avg Credit/Hour ($api),StdDev");
}
print("\n");

foreach my $gpu (nsort(keys %gpuToStats))
{
    print("$gpu");
    foreach my $api (@SORTED_APIS)
    {
        unless(defined($gpuToStats{$gpu}{$api}))
        {
            print(",,");
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

        # Sort highest CPH results first
        @results = sort { $b->{"cph"} <=> $a->{"cph"} } @results;

        my $sum = 0;
        my $sum2 = 0;

        if($n > 2 * $MIN_HOST_IDS)
        {
            $n = int($n / 4); # Avg top quarter if we have a lot
        }
        else
        {
            $n = int($n / 2); # Only average top half
        }

        for(my $i = 0; $i < $n; ++$i)
        {
            my $c = $results[$i]->{"cph"};

            $sum += $c;
            $sum2 += $c * $c;
        }

        my $avg = $sum / $n;
        my $stddev = sqrt(($sum2 / $n) - ($avg * $avg));

        print(",$avg,$stddev");
    }

    print("\n");
}

print("\nGPU");
foreach my $api (@SORTED_APIS)
{
    print(",Avg Credit/Watt-Hour ($api),StdDev");
}
print("\n");

foreach my $gpu (nsort(keys %gpuToStats))
{
    print("$gpu");
    foreach my $api (@SORTED_APIS)
    {
        unless(defined($gpuToStats{$gpu}{$api}))
        {
            print(",,");
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

        unless(defined($hardwareStats{$gpu}))
        {
            print("$gpu not in hardware stats table\n");
            next;
        }

        my $tdp = $hardwareStats{$gpu}{tdp};

        # Sort highest CPH results first
        @results = sort { $b->{"cph"} <=> $a->{"cph"} } @results;

        my $sum = 0;
        my $sum2 = 0;

        if($n > 2 * $MIN_HOST_IDS)
        {
            $n = int($n / 4); # Avg top quarter if we have a lot
        }
        else
        {
            $n = int($n / 2); # Only average top half
        }

        for(my $i = 0; $i < $n; ++$i)
        {
            my $c = $results[$i]->{"cph"};

            $c /= $tdp;

            $sum += $c;
            $sum2 += $c * $c;
        }

        my $avg = $sum / $n;
        my $stddev = sqrt(($sum2 / $n) - ($avg * $avg));

        print(",$avg,$stddev");
    }
    print("\n");
}
