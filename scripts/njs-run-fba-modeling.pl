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
use Bio::KBase::workspace::ScriptHelpers qw(workspaceURL get_ws_client);
use Bio::KBase::fbaModelServices::ScriptHelpers qw(getToken get_workspace_object fbaws printJobData get_fba_client runFBACommand universalFBAScriptCode );

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
my $fba;
#if (defined($parameters->{localmode}) && $parameters->{localmode} == 1) {
if (!$ENV{FBA_SERVER_MODE}) {
	$Bio::KBase::fbaModelServices::Server::CallContext = {token => $ENV{KB_AUTH_TOKEN}};
	require "Bio/KBase/fbaModelServices/Impl.pm";
	$fba = Bio::KBase::fbaModelServices::Impl->new({"workspace-url" => workspaceURL()});
} else {
	$fba = get_fba_client($service_url);
}
#Running command
my $finalparameters = {};
my $genomeset;
my $modelset;
foreach my $key (keys(%{$parameters})) {
	if (defined($parameters->{$key}) && length($parameters->{$key}) > 0) {
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
		if ($key eq "community_model_set") {
			($modelset,my $info) = get_workspace_object($parameters->{workspace}."/".$finalparameters->{$key});
		}
		if ($key eq "community_submodel_ids") {
			$finalparameters->{models} = [];
			for (my $i=0; $i < @{$finalparameters->{community_submodel_ids}}; $i++) {
				push(@{$finalparameters->{models}},[$finalparameters->{community_submodel_ids}->[$i],$finalparameters->{workspace},1]);
			}
			delete $finalparameters->{community_submodel_ids};
		}
		if ($key eq "genome_workspaces" && defined($parameters->{genomes})) {
			$finalparameters->{genome_workspaces} = [];
			for (my $i=0; $i < @{$parameters->{genomes}}; $i++) {
				push(@{$finalparameters->{genome_workspaces}},$parameters->{workspace});
			}
		}
		if ($key eq "pangenome_set") {
			($genomeset,my $info) = get_workspace_object($parameters->{workspace}."/".$finalparameters->{$key});
		}
	}
}
if (defined($modelset) && $command eq "models_to_community_model") {
	my $hash;
	my $count = 0;
	if (defined($finalparameters->{models})) {
		for (my $i=0; $i < @{$finalparameters->{models}}; $i++) {
			if (!defined($hash->{$finalparameters->{models}->[$i]->[1]."/".$finalparameters->{models}->[$i]->[0]})) {
				$hash->{$finalparameters->{models}->[$i]->[1]."/".$finalparameters->{models}->[$i]->[0]} = $finalparameters->{models}->[$i]->[2];
				$count++;
			}
		}
	}
	foreach my $key (keys(%{$modelset->{"elements"}})) {
		my $ref = $modelset->{"elements"}->{$key}->{"ref"};
		my $array = [split(/\//,$ref)];
		my $abundance = 1;
		if (defined($modelset->{"elements"}->{$key}->{metadata}->{abundance})) {
			$abundance = $modelset->{"elements"}->{$key}->{metadata}->{abundance};
		}
		if (!defined($hash->{$array->[0]."/".$array->[1]})) {
			$hash->{$array->[0]."/".$array->[1]} = $abundance;
			$count++;
		}
	}
	$finalparameters->{models} = [];
	foreach my $item (keys(%{$hash})) {
		my $array = [split(/\//,$item)];
		push(@{$finalparameters->{models}},[$array->[1],$array->[0],$hash->{$item}]);
	}
}
if (defined($genomeset)) {
	my $hash;
	my $count = 0;
	if (defined($finalparameters->{genomes})) {
		for (my $i=0; $i < @{$finalparameters->{genome_workspaces}}; $i++) {
			if (!defined($hash->{$finalparameters->{genome_workspaces}->[$i]."/".$finalparameters->{genomes}->[$i]})) {
				$hash->{$finalparameters->{genome_workspaces}->[$i]."/".$finalparameters->{genomes}->[$i]} = $count;
				$count++;
			}
		}
	}
	foreach my $key (keys(%{$genomeset->{"elements"}})) {
		my $ref = $genomeset->{"elements"}->{$key}->{"ref"};
		my $array = [split(/\//,$ref)];
		if (!defined($hash->{$array->[0]."/".$array->[1]})) {
			$hash->{$array->[0]."/".$array->[1]} = $count;
			$count++;
		}
	}
	$finalparameters->{genomes} = [];
	$finalparameters->{genome_workspaces} = [];
	foreach my $item (keys(%{$hash})) {
		my $array = [split(/\//,$item)];
		push(@{$finalparameters->{genomes}},$array->[1]);
		push(@{$finalparameters->{genome_workspaces}},$array->[0]);
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
my $JSON = JSON->new->utf8(1);
my $output;
eval {
	$output = $fba->$command($finalparameters);
};
if (!defined($output)) {
	die $@;
}
if ($command eq "metagenome_to_fbamodels") {
	my $object = {
		type => "KBaseFBA.FBAModelSet",
		data => {
			description => "Set of models generated from metagenome ".$finalparameters->{workspace}."/".$finalparameters->{metaanno_uid},
			elements => {}
		},
		provenance => [{
			"time" => DateTime->now()->datetime()."+0000",
			service_ver => $fba->version(),
			service => "KBaseFBAModeling",
			method => $command,
			method_params => [$parameters],
			input_ws_objects => [],
			resolved_ws_objects => [],
			intermediate_incoming => [],
			intermediate_outgoing => []
		}],
	};
	for (my $i=0; $i < @{$output}; $i++) {
		$object->{data}->{elements}->{$output->[$i]->[7]."/".$output->[$i]->[1]} = {
			"ref" => $output->[$i]->[6]."/".$output->[$i]->[0]."/".$output->[$i]->[4],
			metadata => {
				otu => $output->[$i]->[10]->{Name},
				numreactions => $output->[$i]->[10]->{"Number reactions"}	
			}
		};
	}
	if ($finalparameters->{modelset_id} =~ m/^\d+$/) {
		$object->{objid} = $finalparameters->{modelset_id};
	} else {
		$object->{name} = $finalparameters->{modelset_id};
	}	
	my $input = {
		objects => [$object], 	
	};
	if ($finalparameters->{workspace}  =~ m/^\d+$/) {
	   	$input->{id} = $finalparameters->{workspace};
	} else {
	   	$input->{workspace} = $finalparameters->{workspace};
	}
	my $ws = get_ws_client($ws_url);
	$output = $ws->save_objects($input);
}
print STDOUT $JSON->encode($output);
