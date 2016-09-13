#!/usr/bin/perl

use strict;
use warnings;

my $MAX_HOSTS = 10000;
my $BASE_URL = "http://setiathome.berkeley.edu/host_app_versions.php?hostid=";

sub CheckHost($)
{
    my $hid = shift;

    my $url = $BASE_URL . $hid;
    my $app = "stock";

    my $curl;
    open($curl, "curl --silent $url 2>&1 |") or die;

    while(<$curl>)
    {
        if(/anonymous platform/)
        {
            $app = "anonymous";
            last;
        }
    }

    close($curl);

    print("$hid,$app\n");

    sleep(1);
}

open(my $fd, "topHosts.csv") or die;

while(<$fd>)
{
    if(/^([0-9]*),(.*)/)
    {
        CheckHost($1);

        unless(--$MAX_HOSTS)
        {
            last;
        }
    }
}
