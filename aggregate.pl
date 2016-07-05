use strict;
use warnings;

use Scalar::Util qw(looks_like_number);

my $ROWS_PER_PAGE = 20;
my $MAX_ROWS = 100;
my $APP_ID = 29; # SETI@home v8

print("Host, Device, Credit/Hour, Work Units\n");

foreach my $HOST_ID (@ARGV)
{
    my %stats = (
        'gpu' => {'credit' => 0, 'runTime' => 0, 'n' => 0},
        'cpu' => {'credit' => 0, 'runTime' => 0, 'n' => 0}
    );

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
    $gpuModel =~ s/\bNVIDIA\b/ /i;
    $gpuModel =~ s/\([0-9]+MB\)//;
    $gpuModel =~ s/ driver: .*//;
    $gpuModel =~ s/\s*$//;
    $gpuModel =~ s/^\s*//;

    # Intel(R) Xeon(R) CPU           W3550  @ 3.07GHz [Family 6 Model 26 Stepping 5]
    $cpuModel =~ s/\[Family.*//;
    $cpuModel =~ s/\bIntel\b/ /;
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
                        my $statsKey = ($application =~ /opencl/) ||
                            ($application =~ /\bGPU\b/i) ? 'gpu' : 'cpu';

                        $stats{$statsKey}{'credit'} += $credit;
                        $stats{$statsKey}{'runTime'} += $runTime;
                        $stats{$statsKey}{'n'} += 1;

                        my $cph = (60 * 60 * $credit) / $runTime;
                        #print("$id $cph CR/h $statsKey\n");
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
            print("Parsed $rows/$ROWS_PER_PAGE from HTML\n");
            last;
        }
    }

    foreach my $key (sort keys(%stats))
    {
        if($stats{$key}{'n'} <= 0)
        {
            next;
        }
       
        my $n = $stats{$key}{'n'};
        my $credit = $stats{$key}{'credit'};
        my $runTime = $stats{$key}{'runTime'};
        
        my $cph = (60 * 60 * $credit) / $runTime;

        if($key eq 'cpu')
        {
            $cph *= $cpuCount;
            $key = $cpuModel;
        }
        elsif($key eq 'gpu')
        {
            $key = $gpuModel;
        }
        print("$HOST_ID, $key, $cph, $n\n");
    }
}

