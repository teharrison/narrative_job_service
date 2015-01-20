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
use GenomeComparisonClient;
use Bio::KBase::userandjobstate::Client;
use Bio::KBase::fbaModelServices::ScriptHelpers qw(fbaws printJobData get_fba_client runFBACommand universalFBAScriptCode );
#Defining globals describing behavior
my $usage = "Usage:\nnjs-genome-comparison <Command name> <Parameters file> <Service URL> <UJS URL>\n";
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
	$ARGV[2] = "https://kbase.us/services/genome_comparison/jsonrpc";
}
if (!defined($ARGV[3])) {
	$ARGV[3] = "https://kbase.us/services/userandjobstate";
}
#Selecting command
my $command = $ARGV[0];
if ($ARGV[0] ne "blast_proteomes") {
	print "[error] command $command not supported!\n";
	exit 1;
}
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
my $GenComp = GenomeComparisonClient->new($url);
#Running command
my $finalparameters = {};
foreach my $key (keys(%{$parameters})) {
	if (length($parameters->{$key}) > 0) {
		my $array = [split(/:/,$key)];
		my $current = $finalparameters;
		for (my $i = 0; $i < @{$array}; $i++) {
			if (defined($array->[$i+1])) {
				if (!defined($current->{$array->[$i]})) {
					$current->{$array->[$i]} = {};
				}
				$current = $current->{$array->[$i]};
			} else {
				$current->{$array->[$i]} = $parameters->{$key};
			}
		}
	}
}
my $jobid = $GenComp->$command($finalparameters);
my $ujs = Bio::KBase::userandjobstate::Client->new($ARGV[3]);
my $jobinfo = $ujs->get_job_info($jobid);
my $continue = 1;
while ($continue) {
	$jobinfo = $ujs->get_job_info($jobid);
	if ($jobinfo->[10] == 1) {
		$continue = 0;
	}
}
my $JSON = JSON->new->utf8(1);
print STDOUT $JSON->encode([$jobinfo]);