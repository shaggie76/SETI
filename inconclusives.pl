#!/usr/bin/perl

use strict;
use warnings;

use File::Path;
use Digest::MD5 qw(md5_hex);

my $ROWS_PER_PAGE = 20;
my $MAX_ROWS = 2000;
my $APP_ID = 29; # SETI@home v8

my $MAX_HOSTS = 0xFFFFFFFF;

my @hostIds = ();

my %API_PRETTY = ( 'opencl' => 'OpenCL', 'cuda' => 'CUDA', 'gpu' => 'Anonymous' );

foreach my $arg (@ARGV)
{
    if($arg =~ /^\d+$/)
    {
        push(@hostIds, $arg);
        next;
    }

    die("Bad arg: $arg\n");
}

foreach my $scanHostId (@hostIds)
{
    my $cpuCount;
    my $gpuModel;
    my $cpuModel;

    my $url = "http://setiathome.berkeley.edu/show_host_detail.php?hostid=$scanHostId";

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

    my $BASE_URL = "http://setiathome.berkeley.edu";

    my @row;
    my $rows = 0;

    my %workUnitToTaskName;

    for(my $offset = 0; $offset < $MAX_ROWS; $offset += $ROWS_PER_PAGE)
    {
        my $url = "$BASE_URL/results.php?hostid=$scanHostId&offset=$offset&show_names=1&state=3&appid=$APP_ID";

        my $curl;
        open($curl, "curl --silent \"$url\" |") or die;

        my @row;
        my $rows = 0;

        while(<$curl>)
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
                    my $wuId = $row[-8];
                    my $taskName = $row[-9];
                    $taskName =~ s/_\d$//;

                    $workUnitToTaskName{$wuId} = $taskName;
                    ++$rows;
                }
                @row = ();
            }
        }

        close($curl);

        if($rows < $ROWS_PER_PAGE)
        {
            last;
        }
    }

    # check output dir for previously discovered but unresolved 
    
    my $outPrefix = "Inconclusives/$scanHostId/";

    foreach my $outPath (glob("Inconclusives/$scanHostId/[0-9]*"))
    {
        my $index;

        unless(open($index, "$outPath/index.txt"))
        {
            print("$outPath/index.txt not found\n");
            next;
        }

        my $wuId = substr($outPath, length($outPrefix));

        my $taskName = <$index>;
        chomp($taskName);
        close($index);

        unless(defined($workUnitToTaskName{$wuId}))
        {
            $workUnitToTaskName{$wuId} = $taskName;
        }
    }

    # Inconclusives/$hostId/$wuId/index.txt $resultId.txt for each stdout

    foreach my $wuId (sort keys %workUnitToTaskName)
    {
        my $taskName = $workUnitToTaskName{$wuId};
        print("Checking WU $wuId $taskName\n");

        my $url = "$BASE_URL/workunit.php?wuid=$wuId";
        my @resultIds;

        my $curl;
        open($curl, "curl --silent \"$url\" |") or die;
        while(<$curl>)
        {
            if(/Task.*click for details/)
            {
                last;
            }
        }

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
                /result\.php\?resultid=(\d+)\"\>/ ||
                /show_host_detail\.php\?hostid=(\d+)/ ||
                /\<td[^\>]*\>(.*)\<\/td\>/ 
            )
            {
                push(@row, $1);
            }

            if(/\<\/tr\>/)
            {
                if(scalar(@row) >= 9)
                {
                    my $application = $row[-1];
                    my $credit = $row[-2];
                    my $cpuTime = $row[-3];
                    my $runTime = $row[-4];
                    my $status = $row[-5];
                    my $reported = $row[-6];
                    my $issued = $row[-7];
                    my $hostId = $row[-8];
                    my $resultId = $row[-9];

                    # Unsent results will have hostId "---" but the resultId will be valid

                    push(@resultIds, $resultId);

                    ++$rows;
                }
                @row = ();
            }
        }

        close($curl);

        # Write the index
        my $outPath = "$outPrefix/$wuId";
        mkpath($outPath);

        my $index;
        open($index, "> $outPath/index.txt") or die;
        print($index "$taskName\n");
        print($index join(",", @resultIds) . "\n");
        close($index);
        
        my $dataFile = "$outPath/$taskName";

        unless(-f $dataFile)
        {
            # http://setiathome.berkeley.edu/forum_thread.php?id=56536&postid=953939#953939
            my $DL_BASE_URL = 'http://boinc2.ssl.berkeley.edu/sah/download_fanout';
            
            my $digest = md5_hex($taskName);
            my $d1 = substr($digest, 5, 1);
            $d1 =~ tr/048c159d26ae37bf/0000111122223333/;

            my $d3 = $d1 . substr($digest, 6, 2);
            $d3 =~ s/^0+//;
           
            $url = "$DL_BASE_URL/$d3/$taskName";
            
            print("Downloading work-unit...\n");
            system("curl --silent -o $dataFile \"$url\"");
        }

        my @pending;

        # Get the output of each contributing result
        foreach my $resultId (@resultIds)
        {
            my $resultFile = "$outPath/$resultId.html";

            if(-f $resultFile)
            {
                print("Cached result $resultId\n");
                next;
            }
            
            $url = "$BASE_URL/result.php?resultid=$resultId";

            my @result;
            my $over = 0;

            open($curl, "curl --silent \"$url\" |") or die;

            while(<$curl>)
            {
                push(@result, $_);
                if(/Server state.*Over/)
                {
                    $over = 1;
                }
            }
            close($curl);

            if($over)
            {
                print("Saving result $resultId...\n");
                my $resultFd;
                open($resultFd, "> $resultFile") or die;
                foreach(@result)
                {
                    print($resultFd $_);
                }
                close($index);
            }
            else
            {
                push(@pending, $resultId);
            }
        }

        if(@pending)
        {
            print("Pending result " . join(" and ", @pending) . "\n");
        }
        else
        {
            print("Validation concluded.\n");
        }

        print("\n");
    }
}
