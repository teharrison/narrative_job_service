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
use Getopt::Long;
use GenomeComparisonClient;
use Bio::KBase::userandjobstate::Client;
use Bio::KBase::workspace::ScriptHelpers qw(workspaceURL get_ws_client);
use Bio::KBase::fbaModelServices::ScriptHelpers qw(fbaws printJobData get_fba_client runFBACommand universalFBAScriptCode);

#Defining globals describing behavior
my $command     = "";
my $param_file  = "parameters.json";
my $service_url = "https://kbase.us/services/genome_comparison/jsonrpc";
my $ws_url  = "http://kbase.us/services/ws";
my $ujs_url = "https://kbase.us/services/userandjobstate";
my $help    = 0;
my $usage   = "Usage:\nnjs-genome-comparison --command <Command name> --param_file <Parameters file> --service_url <Service URL> --ws_url <Workspace URL> --ujs_url <User and Job State URL>\n";
my $options = GetOptions (
    "command=s"     => \$command,
	"param_file=s"  => \$param_file,
	"service_url=s" => \$service_url,
	"ws_url=s"      => \$ws_url,
	"ujs_url=s"     => \$ujs_url,
	"help!"         => \$help
);
if ($help){
    print $usage;
    exit 0;
}
if (! $command) {
    print STDERR "[error] missing command\n$usage";
    exit 1;
}
if ($command ne "blast_proteomes") {
    print STDERR "[error] command '$command' is not supported\n$usage";
    exit 1;
}
if (! -e $param_file) {
    print STDERR "[error] parameter file is missing\n$usage";
    exit 1;
}

#Loading parameters from file
open(my $fh, "<", $param_file);
my $parameters;
{
    local $/;
    my $str = <$fh>;
    $parameters = decode_json $str;
}
close($fh);

#Set workspace url
workspaceURL($ws_url);
#Retrieving service client or server object
my $GenComp = GenomeComparisonClient->new($service_url);
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
my $ujs = Bio::KBase::userandjobstate::Client->new($ujs_url);
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
