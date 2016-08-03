use strict;
use warnings;

use Scalar::Util qw(looks_like_number);

my $ROWS_PER_PAGE = 20;
my $MAX_ROWS = 200;
my $APP_ID = 29; # SETI@home v8

my $MAX_HOSTS = 0xFFFFFFFF;

print("Host, API, Device, Credit, Seconds, Credit/Hour, Work Units\n");

my $cpu = 1;
my $gpu = 1;
my $anon = 0;
my $verbose = 0;

foreach my $HOST_ID (@ARGV)
{
    if($HOST_ID eq "-gpu")
    {
        $cpu = 0;
        next;
    }

    if($HOST_ID eq "-cpu")
    {
        $gpu = 0;
        next;
    }

    if($HOST_ID eq "-anon")
    {
        $anon = 1;
        next;
    }

    if($HOST_ID eq "-v")
    {
        $verbose = 1;
        next;
    }

    if($HOST_ID =~ /-max=([0-9]*)/)
    {
        $MAX_HOSTS = int($1);
        next;
    }

    my %stats;

    my $cpuCount;
    my $gpuModel;
    my $cpuModel;

    my $url = "http://setiathome.berkeley.edu/show_host_detail.php?hostid=$HOST_ID";

    my $curl;
    open($curl, "curl --silent $url |") or die;

    while(<$curl>)
    {
        if(/>Number of processors.*>([0-9]*)<\/td>/)
        {
            $cpuCount = $1;        
        }
        elsif(/>Coprocessors.*>([^>]*)<\/td>/)
        {
            $gpuModel = $1;        
        }
        elsif(/>CPU type.*>([^>]*)<\/td>/)
        {
            $cpuModel = $1;        
        }
    }

    close($curl);

    unless($cpuCount && $gpuModel && $cpuModel)
    {
        die("Could not get host info from $url\n");
    }

    # NVIDIA GeForce GTX 750 Ti (2048MB) driver: 368.39 OpenCL: 1.2
    $gpuModel =~ s/\([0-9]+MB\)//;
    $gpuModel =~ s/ driver: .*//;
    $gpuModel =~ s/ OpenCL: .*//;

    # Note: Copy/paste below and in scanHosts.pl
    $gpuModel =~ s/\(R\)/ /g;
    $gpuModel =~ s/\(TM\)/ /g;
    $gpuModel =~ s/\s+/ /g;
    $gpuModel =~ s/\s*$//;
    $gpuModel =~ s/^\s*//;

    # Intel(R) Xeon(R) CPU           W3550  @ 3.07GHz [Family 6 Model 26 Stepping 5]
    $cpuModel =~ s/\[Family.*//;
    $cpuModel =~ s/ CPU / /;

    $cpuModel =~ s/\(R\)/ /g;
    $cpuModel =~ s/\(TM\)/ /g;
    $cpuModel =~ s/\s+/ /g;
    $cpuModel =~ s/\s*$//;
    $cpuModel =~ s/^\s*//;

    my $BASE_URL = "http://setiathome.berkeley.edu/results.php";

    for(my $offset = 0; $offset < $MAX_ROWS; $offset += $ROWS_PER_PAGE)
    {
        #By UID $BASE_URL?userid=$USER_ID&offset=$offset&show_names=0&state=4&appid=$APP_ID
        my $url = "$BASE_URL?hostid=$HOST_ID&offset=$offset&show_names=0&state=4&appid=$APP_ID";

        # print("$url\n");

        my $curl;
        open($curl, "curl --silent $url |") or die;

        my @row;
        my $rows = 0;

        while(<$curl>)
        {
            if(/\<tr\>/)
            {
                @row = ();
            }
        
            if
            (
                /result\.php\?(resultid=\d+)/ ||
                /workunit\.php\?(wuid=\d+)/ ||
                /\<td[^\>]*\>(.*)\<\/td\>/ 
            )
            {
                push(@row, $1);
            }

            if(/\<\/tr\>/)
            {
                if(scalar(@row) >= 8)
                {
                    # Look at last n columns to ignore differences in schema
                    # for by-host/by-user
                    my $application = $row[-1];
                    my $credit = $row[-2];
                    my $cpuTime = $row[-3];
                    my $runTime = $row[-4];
                    my $status = $row[-5];
                    my $reported = $row[-6];
                    my $issued = $row[-7];
                    my $id = $row[-8];

                    # looks_like_number doesn't enjoy digit-sep commas
                    $credit =~ s/,//g;
                    $cpuTime =~ s/,//g;
                    $runTime =~ s/,//g;

                    if(looks_like_number($cpuTime) && looks_like_number($credit))
                    {
                        if
                        (
                            ($anon && ($application =~ /Anonymous/)) ||
                            (!$anon && !($application =~ /Anonymous/))
                        )
                        {
                            my $statsKey = 'cpu';
                            
                            if($application =~ /\bopencl/i)
                            {
                                $statsKey = 'opencl';
                            }
                            elsif($application =~ /\bcuda/i)
                            {
                                $statsKey = 'cuda';
                            }
                            elsif($application =~ /\bgpu\b/i)
                            {
                                # Anon -- not defined
                                $statsKey = 'gpu';
                            }
                            
                            if(defined($stats{$statsKey}))
                            {
                                $stats{$statsKey}{'credit'} += $credit;
                                $stats{$statsKey}{'runTime'} += $runTime;
                                $stats{$statsKey}{'n'} += 1;
                            }
                            else
                            {
                                $stats{$statsKey}{'credit'} = $credit;
                                $stats{$statsKey}{'runTime'} = $runTime;
                                $stats{$statsKey}{'n'} = 1;
                            }

                            if($verbose)
                            {
                                my $cph = (60 * 60 * $credit) / $runTime;
                                print("$id $cph CR/h $statsKey\n");
                            }
                        }

                        ++$rows;
                    }
                    else
                    {
                        print("Ignoring " . join("\n", @row) . "\n");
                    }
                }
                @row = ();
            }
        }

        close($curl);

        if($rows < $ROWS_PER_PAGE)
        {
            #print("Parsed $rows/$ROWS_PER_PAGE from HTML\n");
            last;
        }
    }

    my $haveStats = 0;

    foreach my $key (sort keys(%stats))
    {
        if($stats{$key}{'n'} <= 0)
        {
            next;
        }

        if($key eq 'cpu')
        {
            unless($cpu)
            {
                next;
            }
        }
        else
        {
            unless($gpu)
            {
                next;
            }
        }
       
        my $n = $stats{$key}{'n'};
        my $credit = $stats{$key}{'credit'};
        my $runTime = $stats{$key}{'runTime'}; # Seconds
        
        my $cph = (60 * 60 * $credit) / $runTime;

        my $name = $key;

        if($name eq 'cpu')
        {
            $cph *= $cpuCount;
            $runTime /= $cpuCount;
            $name = $cpuModel;
        }
        else
        {
            $name = $gpuModel;
        }
        print("$HOST_ID, $key, $name, $credit, $runTime, $cph, $n\n");

        if($stats{$key}{'n'} >= 25)
        {
            $haveStats = 1;
        }
    }

    if($haveStats)
    {
        --$MAX_HOSTS;

        if(!$MAX_HOSTS)
        {
            last;        
        }
    }
}

