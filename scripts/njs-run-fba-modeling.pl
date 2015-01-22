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
use Bio::KBase::workspace::ScriptHelpers qw(workspaceURL);
use Bio::KBase::fbaModelServices::ScriptHelpers qw(fbaws printJobData get_fba_client runFBACommand universalFBAScriptCode );

#Defining globals describing behavior
my $command     = "";
my $param_file  = "parameters.json";
my $service_url = "http://kbase.us/services/KBaseFBAModeling";
my $ws_url  = "http://kbase.us/services/ws";
my $help    = 0;
my $usage   = "Usage:\nnjs-run-fba-modeling --command <Command name> --param_file <Parameters file> --service_url <Service URL> --ws_url <Workspace URL>\n";
my $options = GetOptions (
    "command=s"     => \$command,
	"param_file=s"  => \$param_file,
	"service_url=s" => \$service_url,
	"ws_url=s"      => \$ws_url,
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
my $fba = get_fba_client($service_url);
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
		if ($key eq "community_submodel_ids") {
			$finalparameters->{models} = [];
			for (my $i=0; $i < @{$finalparameters->{community_submodel_ids}}; $i++) {
				push(@{$finalparameters->{models}},[$finalparameters->{community_submodel_ids}->[$i],$finalparameters->{workspace},1]);
			}
			delete $finalparameters->{community_submodel_ids};
		}
		if ($key =~ m/workspaces$/) {
			my $idkey = $parameters->{$key};
			$finalparameters->{$key} = [];
			for (my $i=0; $i < @{$parameters->{$idkey}}; $i++) {
				push(@{$finalparameters->{$key}},$finalparameters->{workspace});
			}
		}
	}
}
if ($command eq "runfba" && !defined($finalparameters->{formulation}->{media})) {
	$finalparameters->{formulation}->{media} = "Complete";
	$finalparameters->{formulation}->{media_workspace} = "KBaseMedia";
}
if ($command eq "gapfill_model" && !defined($finalparameters->{formulation}->{formulation}->{media})) {
	$finalparameters->{formulation}->{formulation}->{media} = "Complete";
	$finalparameters->{formulation}->{formulation}->{media_workspace} = "KBaseMedia";
}


my $output = $fba->$command($finalparameters);
my $JSON = JSON->new->utf8(1);
print STDOUT $JSON->encode($output);
