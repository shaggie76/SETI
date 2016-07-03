use strict;
use warnings;

use Scalar::Util qw(looks_like_number);

# TODO: multiply CPU throughput by CPU-threads (same for GPU?)

my $HOST_ID = shift;
my $APP_ID = 29; # SETI@home v8

my $ROWS_PER_PAGE = 20;
my $MAX_ROWS = 100;

my %stats = (
    'gpu' => {'credit' => 0, 'runTime' => 0, 'n' => 0},
    'cpu' => {'credit' => 0, 'runTime' => 0, 'n' => 0}
);

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
                    print("$id $cph CR/h $statsKey\n");
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

foreach my $key (keys(%stats))
{
    if($stats{$key}{'n'} <= 0)
    {
        next;
    }
   
    my $n = $stats{$key}{'n'};
    my $credit = $stats{$key}{'credit'};
    my $runTime = $stats{$key}{'runTime'};
    
    my $cph = (60 * 60 * $credit) / $runTime;
    print("$key average $cph CR/h ($n results)\n");
}


