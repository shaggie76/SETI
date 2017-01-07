#!/usr/bin/perl

# wget http://setiathome.berkeley.edu/stats/host.gz
# then scanHosts.pl | tee GPUs.csv
use strict;
use warnings;

my $MIN_CREDITS = 10000;
my $MIN_RPC_TIME = time() - (7 * 24 * 60 * 60);

# AMD GCN GPU recognition fixed in 7.6.33
my $MIN_VERSION_X = 7;
my $MIN_VERSION_Y = 6;
my $MIN_VERSION_Z = 33;

sub CheckBoincVersion($$$)
{
    my $x = shift;

    if($x < $MIN_VERSION_X)
    {
        return 0;
    }

    if($x > $MIN_VERSION_X)
    {
        return 1;
    }

    my $y = shift;

    if($y < $MIN_VERSION_Y)
    {
        return 0;
    }

    if($y > $MIN_VERSION_Y)
    {
        return 1;
    }

    my $z = shift;

    if($z < $MIN_VERSION_Z)
    {
        return 0;
    }

    if($z > $MIN_VERSION_Z)
    {
        return 1;
    }

    return 1;
}

sub CheckHost($$$$)
{
    my $id = shift;
    my $total_credit = shift;
    my $rpc_time = shift;
    my $coprocs = shift;

    #print("$id,$total_credit,$rpc_time,$coprocs\n");

    if($total_credit < $MIN_CREDITS)
    {
        return;
    }

    if($rpc_time < $MIN_RPC_TIME)
    {
        return;
    }

    # [BOINC|7.6.22]
    if($coprocs =~ /\[BOINC\|([0-9]+)\.([0-9]+)\.([0-9]+)\]/)
    {
        unless(CheckBoincVersion($1, $2, $3))
        {
            return;
        }
    }
    else
    {
        return;
    }

    $coprocs =~ s/\[BOINC\|[0-9.]*\]//g;

    # [vbox|5.0.20r106931]
    $coprocs =~ s/\[vbox\|[^\]]*\]//g;

    # [CUDA|GeForce GTX 750 Ti|2|2048MB|36510|102][INTEL|Intel(R) HD Graphics 4000|1|1246MB||102][vbox|5.0.20]    
    if($coprocs =~ /\]\[/)
    {
        #print("Ignoring multi-gpu $coprocs\n");
        return;
    }

    # [CUDA|GeForce GTX 750 Ti|2|2048MB|36510|102]
    my @cp = split(/\|/, $coprocs);

    if(scalar(@cp) < 3)
    {
        #print("Ignoring multi-core $coprocs\n");
        return;
    }

    unless($cp[2] eq '1')
    {
        #print("Ignoring $coprocs\n");
        return; # ignore multi-gpu
    }

    $coprocs = $cp[1];

    # Note: copy/paste in aggregate.pl
    $coprocs =~ s/ \(\S+\)$//g;
    $coprocs =~ s/\(R\)/ /g;
    $coprocs =~ s/\(TM\)/ /g;
    $coprocs =~ s/\s+/ /g;
    $coprocs =~ s/\s*$//;
    $coprocs =~ s/^\s*//; 
    $coprocs =~ s/^ATI Radeon/AMD Radeon/i;

    # Recent bug in web site actually prints:
    # AMD AMD Radeon (TM) R9 Fury Series (4096MB) OpenCL: 2.0
    $coprocs =~ s/^AMD AMD/AMD/;

    print("$id,$coprocs\n");
}

open(my $fd, 'gunzip -d -c host.gz |') or die;

my $id = 0;
my $total_credit = 0;
my $rpc_time = 0;
my $coprocs = "";

while(<$fd>)
{
    chomp;
    if($_ eq '</host>')
    {
        CheckHost($id, $total_credit, $rpc_time, $coprocs); 
        $id = 0;
        $total_credit = 0;
        $rpc_time = 0;
        $coprocs = "";
    }
    elsif(/<id>([0-9]*)<\/id>/)
    {
        $id = $1;
    }
    elsif(/<total_credit>([^>]*)<\/total_credit>/)
    {
        $total_credit = $1;
    }
    elsif(/<rpc_time>([^>]*)<\/rpc_time>/)
    {
        $rpc_time = $1;
    }
    elsif(/<coprocs>([^>]*)<\/coprocs>/)
    {
        $coprocs = $1;
    }
}

close($fd);

