#!/usr/bin/perl

# wget http://setiathome.berkeley.edu/stats/host.gz
# then rankHosts.pl > topHosts.csv
use strict;
use warnings;

use File::stat;

my @hosts;

my $NOW = stat("host.gz")->mtime;
my $M_LN2 = 0.693147180559945309417;
my $CREDIT_HALF_LIFE = 86400 * 7;
my $SCALE = $M_LN2 / $CREDIT_HALF_LIFE;

open(my $fd, 'gunzip -d -c host.gz |') or die;

sub CheckHost($$$)
{
    my $id = shift;
    my $avg_credit = shift;
    my $avg_time = shift;

    my $diff = $NOW - $avg_time;
    my $weight = exp(-$diff * $SCALE);
    $avg_credit *= $weight;

    $avg_credit = int($avg_credit + 0.5);

    if($avg_credit > 0)
    {
        push(@hosts, { hid => $id, rac => $avg_credit });
    }
}

my $id = 0;
my $expavg_credit = 0;
my $expavg_time = 0;

while(<$fd>)
{
    chomp;
    if($_ eq '</host>')
    {
        CheckHost($id, $expavg_credit, $expavg_time); 
        $id = 0;
        $expavg_credit = 0;
        $expavg_time = 0;
    }
    elsif(/<id>([0-9]*)<\/id>/)
    {
        $id = $1;
    }
    elsif(/<expavg_credit>([^>]*)<\/expavg_credit>/)
    {
        $expavg_credit = 0+$1;
    }
    elsif(/<expavg_time>([^>]*)<\/expavg_time>/)
    {
        $expavg_time = 0+$1;
    }
}

close($fd);

@hosts = sort { $b->{rac} <=> $a->{rac} } @hosts;

foreach my $i (@hosts)
{
    print($i->{hid} . "," . $i->{rac} . "\n");
}
