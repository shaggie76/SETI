use strict;
use warnings;

my $MIN_WORK_UNITS = 25;
my $MIN_HOST_IDS = 10;

my %gpuToStats; # gpu -> hid -> { h => ..., c => ... , w => ... }
my %hardwareStats; # gpu -> { tdp => ..., gf => ... };

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

        if(scalar(@col) != 4)
        {
            print("Parse error: $file $_\n");
            next;
        }

        if($col[0] eq "Host")
        {
            next;
        }

        my $hid = int($col[0]);
        my $gpu = $col[1];
        my $crPerHr = 0+$col[2];
        my $workUnits = int($col[3]);

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

        if
        (
            !defined($gpuToStats{$gpu}{$hid}) ||
            ($gpuToStats{$gpu}{$hid}{"c"} < $crPerHr)
        )
        {
            $gpuToStats{$gpu}{$hid} = { h => $hid, c => $crPerHr, w => $workUnits };
        }
    }

    close($fd);
}

print("GPU,Avg Credit/Hour,StdDev\n");
foreach my $gpu (sort(keys %gpuToStats))
{
    # Convert to array we can sort
    my @results;

    foreach my $hid (keys $gpuToStats{$gpu})
    {
        push(@results, $gpuToStats{$gpu}{$hid});
    }

    my $n = scalar(@results);

    if($n < $MIN_HOST_IDS)
    {
        next;
    }

    # Sort highest results first
    @results = sort { $b->{"c"} <=> $a->{"c"} } @results;

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
        my $c = $results[$i]->{"c"};

        $sum += $c;
        $sum2 += $c * $c;
    }

    my $avg = $sum / $n;
    my $stddev = sqrt(($sum2 / $n) - ($avg * $avg));

    print("$gpu,$avg,$stddev\n");
}

print("\nGPU,Avg Credit/Watt-Hour,StdDev\n");
foreach my $gpu (sort(keys %gpuToStats))
{
    # Convert to array we can sort
    my @results;

    foreach my $hid (keys $gpuToStats{$gpu})
    {
        push(@results, $gpuToStats{$gpu}{$hid});
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

    # Sort highest results first
    @results = sort { $b->{"c"} <=> $a->{"c"} } @results;

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
        my $c = $results[$i]->{"c"};

        $c /= $tdp;

        $sum += $c;
        $sum2 += $c * $c;
    }

    my $avg = $sum / $n;
    my $stddev = sqrt(($sum2 / $n) - ($avg * $avg));

    print("$gpu,$avg,$stddev\n");
}
