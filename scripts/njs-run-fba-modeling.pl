#!/usr/bin/env perl
########################################################################
# Authors: Christopher Henry
# Date: 11/14/2014
# Contact email: chenry@mcs.anl.gov
# Development location: Mathematics and Computer Science Division, Argonne National Lab
########################################################################
use strict;
use warnings;
use JSON::XS;
use Bio::KBase::fbaModelServices::ScriptHelpers qw(fbaws printJobData get_fba_client runFBACommand universalFBAScriptCode );
#Defining globals describing behavior
my $usage = "Usage:\nnjs-run-fba-modeling <Command name> <Parameters file> <Service URL>\n";
if (defined($ARGV[0]) && $ARGV[0] eq "-h") {
	print $usage;
	exit 0;
}
if (!defined($ARGV[0])) {
	print "[error] missing command\n$usage";
	exit 1;
}
if (!defined($ARGV[1])) {
	$ARGV[1] = "parameters.json";
}
if (!defined($ARGV[2])) {
	$ARGV[2] = "http://kbase.us/services/KBaseFBAModeling";
}
#Selecting command
my $command = $ARGV[0];
#Loading parameters from file
open( my $fh, "<", $ARGV[1]);
my $parameters;
{
    local $/;
    my $str = <$fh>;
    $parameters = decode_json $str;
}
close($fh);
#Retrieving service client or server object
my $url = $ARGV[2];
my $fba = get_fba_client($url);
#Running command
my $output = $fba->$command($parameters);
my $JSON = JSON->new->utf8(1);
print STDOUT $JSON->encode($output);
