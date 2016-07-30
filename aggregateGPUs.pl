use strict;
use warnings;

use List::Util qw(shuffle);
use File::stat;

my $MIN_HIDS = 5;
my $MAX_HIDS = 50;

my %gpuToIds;

open(my $fd, "GPUS.csv") or die;
my $sourceStat = stat("GPUs.csv");

while(<$fd>)
{
    if(/^([0-9]*),(.*)/)
    {
        my $hid = $1;
        my $model = $2;

        if(($model =~ /[0-9][0-9][0-9]MX?\b/) || ($model =~ /R9 M\d\d\d/))
        {
            next; # Skip mobile cards
        }

        if
        (
            ($model =~ /\bv[1-9]$/i) ||
            ($model =~ /\bOEM\b/) ||
            ($model =~ /\bION\b/) ||
            ($model =~ /\bBOOST\b/) ||
            ($model =~ /Quadro/) ||
            ($model =~ /Quadro/) ||
            ($model =~ /\bNVS\b/) ||
            ($model =~ s/ \(\d+-bit\)//) ||
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

        if(($model =~ /INTEL.*HD Graphics/i) || ($model =~ /HD Graphics \d\d\d\d/i))
        {
            next; # Skip older generation Intel processors
        }

        if($model =~ /Radeon HD ?\d.\d\d/i)
        {
            next; # Skip older generation AMD processors
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

foreach my $model (reverse sort keys %gpuToIds)
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
