#!/usr/bin/perl

use strict;
use warnings;

use Scalar::Util qw(looks_like_number);

my $ROWS_PER_PAGE = 20;
my $MAX_ROWS = 2000;
my $APP_ID = 29; # SETI@home v8

my $MAX_HOSTS = 0xFFFFFFFF;

my $cpu = 1;
my $gpu = 1;
my $anon = 0;
my $csv = 0;

my @hostIds = ();

my %API_PRETTY = ( 'opencl' => 'OpenCL', 'cuda' => 'CUDA', 'gpu' => 'Anonymous' );

foreach my $arg (@ARGV)
{
    if($arg eq "-gpu")
    {
        $cpu = 0;
        next;
    }

    if($arg eq "-cpu")
    {
        $gpu = 0;
        next;
    }

    if($arg eq "-anon")
    {
        $anon = 1;
        next;
    }

    if($arg eq "-csv")
    {
        $csv = 1;
        next;
    }

    if($arg =~ /-max=([0-9]*)/)
    {
        $MAX_HOSTS = int($1);
        next;
    }

    if($arg =~ /^\d+$/)
    {
        push(@hostIds, $arg);
        next;
    }

    die("Bad arg: $arg\n");
}

if($csv)
{
    print("HostID, ResultID, TaskName, Device, API, Credit, Run-Time, CPU-Time, GPU-Concurrency\n");
}

foreach my $hostId (@hostIds)
{
    my %stats;

    my $cpuCount;
    my $gpuModel;
    my $cpuModel;

    my $url = "http://setiathome.berkeley.edu/show_host_detail.php?hostid=$hostId";

    my $curl;
    open($curl, "curl --silent \"$url\" |") or die;

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
    $gpuModel =~ s/ \([0-9]+MB\)//g;
    $gpuModel =~ s/ driver: [0-9\.]*//g;
    $gpuModel =~ s/ OpenCL: [0-9\.]*//g;

    # Deal with Multi-GPU
    $gpuModel =~ s/ *, */ & /g;

    # Note: Copy/paste below and in scanHosts.pl
    $gpuModel =~ s/\(R\)/ /g;
    $gpuModel =~ s/\(TM\)/ /g;
    $gpuModel =~ s/\s+/ /g;
    $gpuModel =~ s/\s*$//;
    $gpuModel =~ s/^\s*//;

    my $deviceString = $gpuModel;
    my $gpuCount = 1 + ($deviceString =~ tr/&//);

    while($deviceString =~ /\[(\d+)\] /)
    {
        $gpuCount += ($1 - 1);
        $deviceString =~ s/\[\d+\] //;
    }

    # Intel(R) Xeon(R) CPU           W3550  @ 3.07GHz [Family 6 Model 26 Stepping 5]
    $cpuModel =~ s/\[Family.*//;
    $cpuModel =~ s/ CPU / /;

    $cpuModel =~ s/\(R\)/ /g;
    $cpuModel =~ s/\(TM\)/ /g;
    $cpuModel =~ s/\s+/ /g;
    $cpuModel =~ s/\s*$//;
    $cpuModel =~ s/^\s*//;

    my %gpuConcurrency;

    my $BASE_URL = "http://setiathome.berkeley.edu";

    for(my $offset = 0; $offset < $MAX_ROWS; $offset += $ROWS_PER_PAGE)
    {
        my $url = "$BASE_URL/results.php?hostid=$hostId&offset=$offset&show_names=1&state=4&appid=$APP_ID";

        my $curl;
        open($curl, "curl --silent \"$url\" |") or die;
        my @taskPage = <$curl>;
        close($curl);

        my @row;
        my $rows = 0;

        foreach (@taskPage)
        {
            if(/\<tr\>/)
            {
                @row = ();
            }

            if(/result\.php\?resultid=(\d+)\"\>([^<]+)/)
            {
                push(@row, $1, $2);
            }
            elsif
            (
                /workunit\.php\?wuid=(\d+)/ ||
                /\<td[^\>]*\>(.*)\<\/td\>/ 
            )
            {
                push(@row, $1);
            }

            if(/\<\/tr\>/)
            {
                if(scalar(@row) >= 9)
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
                    my $wuId = $row[-8];
                    my $taskName = $row[-9];
                    my $resultId = $row[-10];

                    # looks_like_number doesn't enjoy digit-sep commas
                    $credit =~ s/,//g;
                    $cpuTime =~ s/,//g;
                    $runTime =~ s/,//g;

                    if(looks_like_number($runTime) && looks_like_number($credit))
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
                            $stats{$statsKey}{'cpuTime'} += $cpuTime;
                            $stats{$statsKey}{'n'} += 1;
                        }
                        else
                        {
                            $stats{$statsKey}{'credit'} = $credit;
                            $stats{$statsKey}{'runTime'} = $runTime;
                            $stats{$statsKey}{'cpuTime'} = $cpuTime;
                            $stats{$statsKey}{'n'} = 1;
                        }

                        if(!($statsKey eq 'cpu') && !defined($gpuConcurrency{$statsKey}))
                        {
                            $url = "$BASE_URL/result.php?resultid=$resultId";

                            open($curl, "curl --silent \"$url\" |") or die;
                            my @resultPage = <$curl>;
                            close($curl);

                            $gpuConcurrency{$statsKey} = 1;

                            # TODO: can also check for 
                            # "total_GPU_instances_num set to 5"
                            # and count devices?

                            # TODO: get GPU models from this query instead; would be more accurate

                            # TODO; could, if we cared, get app version

                            foreach (@resultPage)
                            {
                                if(/Number of app instances per device set to:\s*(\d+)/)
                                {
                                    $gpuConcurrency{$statsKey} = $1;
                                    last;
                                }
                            }
                        }

                        if
                        (
                            $csv &&
                            (($statsKey eq 'cpu') ? $cpu : $gpu) &&
                            (
                                ($anon && ($application =~ /Anonymous/)) ||
                                (!$anon && !($application =~ /Anonymous/))
                            )
                        )
                        {
                            if($statsKey eq 'cpu')
                            {
                                my $device = $cpuModel;
                                my $api = 'cpu';
                                print("$hostId, $resultId, $taskName, $device, $api, $credit, $runTime\n");
                            }
                            else
                            {
                                my $device = $gpuModel;
                                my $api = $statsKey;
                                my $gpc = $gpuConcurrency{$statsKey};
                                print("$hostId, $resultId, $taskName, $device, $api, $credit, $runTime, $cpuTime, $gpc\n");
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

        if($rows < $ROWS_PER_PAGE)
        {
            #print("Parsed $rows/$ROWS_PER_PAGE from HTML\n");
            last;
        }
    }

    if($csv)
    {
        my $haveStats = 0;
        
        foreach my $key (sort keys(%stats))
        {
            unless(($key eq 'cpu') ? $cpu : $gpu)
            {
                next;
            }
           
            if($stats{$key}{'n'} >= 25)
            {
                $haveStats = 1;
                last;
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
    else
    {
        my $printHeading = 1;
        my $cpuReserved = 0;

        foreach my $key (sort keys(%stats))
        {
            if($key eq 'cpu')
            {
                next;
            }

            my $runTime = $stats{$key}{'runTime'}; # Seconds
            my $cpuTime = $stats{$key}{'cpuTime'}; # Seconds

            my $cpuUsage = $gpuConcurrency{$key} * $gpuCount * ($cpuTime / $runTime);
            
            if($cpuUsage > $cpuReserved)
            {
                $cpuReserved = $cpuUsage;
            }
        }

        foreach my $key (sort keys(%stats))
        {
            unless(($key eq 'cpu') ? $cpu : $gpu)
            {
                next;
            }

            print("\n");

            if($printHeading)
            {
                print("Host: $hostId");

                if($gpuConcurrency{$key} > 1)
                {
                    print(" ($gpuConcurrency{$key} GPU Tasks / Card)");
                }

                print("\n\n");

                $printHeading = 0;
            }
           
            my $tasks = $stats{$key}{'n'};
            my $credit = $stats{$key}{'credit'};
            my $runTime = $stats{$key}{'runTime'}; # Seconds
            my $cph = (60 * 60 * $credit) / $runTime;

            if($key eq 'cpu')
            {
                print("$cpuModel\n");

                my $count = $cpuCount - $cpuReserved;

                printf("%8.0f Credit / Hour / Core\n", $cph);
                printf("%8.0f Credit / Hour / %.1f Cores\n", $cph * $count, $count);
                printf("%8d Tasks\n", $tasks);
            }
            else
            {
                my $api = $API_PRETTY{$key};
                my $cpuTime = $stats{$key}{'cpuTime'}; # Seconds

                print("$gpuModel ($api)\n");

                $cph *= $gpuConcurrency{$key};

                printf("%8.0f Credit / Hour", $cph);

                if($gpuCount > 1)
                {
                    print(" / Card\n");
                    printf("%8.0f Credit / Hour / %d Cards", $cph * $gpuCount, $gpuCount);
                }

                print("\n");
                printf("%7.0f%% Core / Task\n", 100 * $cpuTime / $runTime);
                printf("%8d Tasks\n", $tasks);
            }
        }
    }
}
