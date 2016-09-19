#!/usr/bin/perl

use strict;
use warnings;

my $fd;
open($fd, "apps.csv") or die;

my @bins;

my $rank = 0;
my $binSize = 10;

my $bin = {binSize => $binSize, anonymous => 0, stock => 0};

while(<$fd>)
{
    chomp;
    my @col = split(/,/, $_);

    if(scalar(@col) != 2)
    {
        print("Parse error: apps.csv $_\n");
        next;
    }

    my $app = $col[1];

    unless($app eq 'anonymous' || $app eq 'stock')
    {
        die;
    }

    ++$bin->{$app};

    ++$rank;
    if($rank == $binSize)
    {
        push(@bins, $bin);
        $binSize = $binSize * 10;

        $bin = { %$bin };
        $bin->{binSize} = $binSize;
    }
}

close($fd);

print("Rank,Anonymous,Stock\n");
foreach $bin (@bins)
{
    my $in = 1.0 / $bin->{binSize};
    my $a = $bin->{anonymous} * $in;
    my $s = $bin->{stock} * $in;

    print($bin->{binSize} . ",$a,$s\n");
}
