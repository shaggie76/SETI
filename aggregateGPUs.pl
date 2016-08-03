use strict;
use warnings;

use Sort::Naturally;

use List::Util qw(shuffle);
use File::stat;

my $MIN_HIDS = 5;
my $MAX_HIDS = 50;

my %gpuToIds;

my @files = sort(glob("Output/*.csv"));

my %knownHIDs;

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
        $knownHIDs{$hid} = 1;
    }

    close($fd);
}

open(my $fd, "GPUS.csv") or die;
my $sourceStat = stat("GPUs.csv");

while(<$fd>)
{
    if(/^([0-9]*),(.*)/)
    {
        my $hid = $1;
        my $model = $2;

        if(defined($knownHIDs{$hid}))
        {
            next;
        }

        $model =~ s/\s+[0-9]+ ?GB$//i; # Ignore on-board memory size for now

        if(($model =~ /[0-9][0-9][0-9]MX?\b/) || ($model =~ /R9 M\d\d\d/))
        {
            next; # Skip mobile cards
        }

        if
        (
            ($model =~ /\bv[1-9]$/i) ||
            ($model =~ /\bOEM\b/) ||
            ($model =~ /\bSE$/) ||
            ($model =~ /\bION\b/) ||
            ($model =~ /\bBOOST\b/) ||
            ($model =~ /\bNVS\b/) ||
            ($model =~ /Quadro/) ||
            ($model =~ /SuperSumo/i) ||
            ($model =~ s/ \(\d+-bit\)$//) ||
            ($model =~ /XT Prototype/i) ||
            ($model =~ /unknown/i)
        )
        {
            next; # Skip weird cards
        }

        if((($model =~ /NVIDIA/i) || ($model =~ /GeForce/i)) && !($model =~ /\bGTX\b/i))
        {
            next; # Skip older generation Nvidia cards
        }

        if($model =~ /GeForce [2-9]\d\d\d/i)
        {
            next; # Skip older generation Nvidia cards
        }

        #if(($model =~ /INTEL.*HD Graphics/i) || ($model =~ /HD Graphics \d\d\d\d/i))
        #{
        #    next; # Skip older generation Intel processors
        #}

        if
        (
            ($model =~ /\bIntel\b/i) ||
            ($model =~ /\bHD Graphics\b/i) ||
            ($model =~ /^Iris\b/i)
        )
        {
            next; # Skip embedded
        }

        if($model =~ /Radeon HD ?\d.\d\d/i)
        {
            next; # Skip older generation AMD processors
        }

        unless($model)
        {
            next;
        }

        if(defined($gpuToIds{$model}))
        {
            push(@{$gpuToIds{$model}}, $hid);
        }
        else
        {
            @{$gpuToIds{$model}} = ($hid);
        }
    }
}

close($fd);

mkdir("Output");

foreach my $model (nsort keys %gpuToIds)
{
    my @hids = @{$gpuToIds{$model}};

    if(scalar(@hids) < $MIN_HIDS)
    {
        next;
    }

    if(scalar(@hids) > $MAX_HIDS)
    {
        @hids = shuffle(@hids);
        @hids = @hids[0 .. $MAX_HIDS];
    }

    print("$model\n");

    my $destFile = "Output/$model.csv";
    my $destStat = stat($destFile);

    if(defined($destStat) && ($sourceStat->mtime <= $destStat->mtime))
    {
        next;
    }

    my $max = $MAX_HIDS / 2; # If you scan half of them you can stop
    my $cmd = "aggregate.pl -gpu -max=$max" . join(" ", @hids);

    my @output;

    open(my $fd, "$cmd |") or die;

    while(<$fd>)
    {
        print($_);
        push(@output, $_);
    }

    close($fd);
   
    open($fd, ">>$destFile") or die;
    print($fd join('', @output));
    close($fd);

    print("\n");
}
