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
    my $defaultGpu;
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
            $defaultGpu = $1;        
        }
        elsif(/>CPU type.*>([^>]*)<\/td>/)
        {
            $cpuModel = $1;        
        }
    }

    close($curl);

    unless($cpuCount && $defaultGpu && $cpuModel)
    {
        die("Could not get host info from $url\n");
    }

    # NVIDIA GeForce GTX 750 Ti (2048MB) driver: 368.39 OpenCL: 1.2
    $defaultGpu =~ s/ \([0-9]+MB\)//g;
    $defaultGpu =~ s/ driver: [0-9\.]*//g;
    $defaultGpu =~ s/ OpenCL: [0-9\.]*//g;

    # Deal with Multi-GPU
    $defaultGpu =~ s/ *, */ & /g;

    # Note: Copy/paste below and in scanHosts.pl
    $defaultGpu =~ s/\(R\)/ /g;
    $defaultGpu =~ s/\(TM\)/ /g;
    $defaultGpu =~ s/\s+/ /g;
    $defaultGpu =~ s/\s*$//;
    $defaultGpu =~ s/^\s*//;

    my $deviceString = $defaultGpu;
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

    my %gpuConcurrency; # api -> concurrency
    my %gpuDevices; # api -> device

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

                            # TODO; could, if we cared, get app version

                            my $parsingDevices = 0;
                            my $pendingDevices;

                            my %devices;

                            foreach (@resultPage)
                            {
                                if(/Number of app instances per device set to:\s*(\d+)/)
                                {
                                    $gpuConcurrency{$statsKey} = $1;
                                    next;
                                }

                                if($csv)
                                {
                                    # don't try to parse when doing batch in CSV; it's not
                                    # well tested and not important to the batch results
                                    # because they discard multi-GPU hosts anyway.
                                    next; 
                                }

                                if(/Number of devices:\s*(\d+)/i)
                                {
                                    $parsingDevices = 1;
                                    $pendingDevices = int($1);
                                    next;
                                }

                                if(/setiathome_CUDA: Found (\d+) CUDA device/)
                                {
                                    $parsingDevices = 1;
                                    $pendingDevices = int($1);
                                    next;
                                }

                                if($parsingDevices)
                                {
                                    if(/^\s*$/)
                                    {
                                        $parsingDevices = 0;
                                        next
                                    }
                                    
                                    if(/^\s*Name:\s*(.*)\s*$/ || /Device \d+: (.*) is okay/)
                                    {
                                        if(defined($devices{$1}))
                                        {
                                            ++$devices{$1};
                                        }
                                        else
                                        {
                                            $devices{$1} = 1;
                                        }
                                        --$pendingDevices;
                                        next;
                                    }
                                }
                            }

                            if($pendingDevices)
                            {
                                print("Could not parse devices from $url\n");
                                $gpuDevices{$statsKey} = $defaultGpu;
                            }
                            elsif(defined($pendingDevices))
                            {
                                my $d = "";

                                foreach my $g (sort {($devices{$a} != $devices{$b}) ? $devices{$b} <=> $devices{$a} : $a cmp $b} keys(%devices))
                                {
                                    if($d)
                                    {
                                        $d .= " & ";
                                    }

                                    my $n = $devices{$g};

                                    if($n > 1)
                                    {
                                        $d .= "[$n] ";
                                    }

                                    $d .= $g;
                                }

                                $gpuDevices{$statsKey} = $d;
                            }
                            else
                            {
                                $gpuDevices{$statsKey} = $defaultGpu;
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
                                my $api = $statsKey;
                                my $device = $gpuDevices{$statsKey};
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
                print("Host: $hostId\n\n");
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
                my $device = $gpuDevices{$key};
                my $cpuTime = $stats{$key}{'cpuTime'}; # Seconds
                my $gpc = $gpuConcurrency{$key};

                print("$device");

                $deviceString = $device;
                my $gpuCount = 1 + ($deviceString =~ tr/&//);

                while($deviceString =~ /\[(\d+)\] /)
                {
                    $gpuCount += ($1 - 1);
                    $deviceString =~ s/\[\d+\] //;
                }

                if($gpc > 1)
                {
                    print(", $gpc Tasks / Card");
                }

                print(" ($api)\n");

                $cph *= $gpc;

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
