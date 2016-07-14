use strict;
use warnings;

use List::Util qw(shuffle);
use File::stat;

my $MIN_HIDS = 10;
my $MAX_HIDS = 40;

my %gpuToIds;

open(my $fd, "GPUS.csv") or die;
my $sourceStat = stat("GPUs.csv");

while(<$fd>)
{
    if(/^([0-9]*),(.*)/)
    {
        my $hid = $1;
        my $model = $2;

        if($model =~ /[0-9][0-9][0-9]MX?\b/)
        {
            next; # Skip mobile cards
        }

        if(($model =~ /\bBOOST\b/) || ($model =~ /  /))
        {
            next; # Skip weird cards
        }

        if(($model =~ /Quadro/) || ($model =~ /\bNVS\b/))
        {
            next;
        }

        $model =~ s/ \(\d+-bit\)//;
        $model =~ s/ oem//;

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

    if(scalar(@hids) < $MAX_HIDS)
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

    my $max = $MIN_HIDS; # scan max but abort after min valid
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
