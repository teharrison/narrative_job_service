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
use DateTime;
use Digest::MD5;
use Bio::KBase::GenomeAnnotation::Client;
use Bio::KBase::workspace::ScriptHelpers qw( get_ws_client workspace workspaceURL parseObjectMeta parseWorkspaceMeta printObjectMeta);
#Defining globals describing behavior
my $usage = "Usage:\nnjs-run-genome-annotation <Command name> <Parameters file> <Service URL> <Workspace URL>\n";
if (defined($ARGV[0]) && $ARGV[0] eq "-h") {
	print $usage;
	exit 0;
}
if (!defined($ARGV[0])) {
	$ARGV[0] = "annotate_genome";
}
if ($ARGV[0] ne "annotate_genome") {
    print "[error] only command 'annotate_genome' is currently supported\n$usage";
    exit 1;
}
if (!defined($ARGV[1])) {
	$ARGV[1] = "parameters.json";
}
if (!defined($ARGV[2])) {
	$ARGV[2] = "http://tutorial.theseed.org/services/genome_annotation";
}
if (!defined($ARGV[3])) {
	$ARGV[3] = "http://kbase.us/services/ws";
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
my $ws = get_ws_client($ARGV[3]);
my $input = {};
if ($parameters->{workspace} =~ m/^\d+$/) {
	$input->{wsid} = $parameters->{workspace};
} else {
	$input->{workspace} = $parameters->{workspace};
}
if ($parameters->{input_contigset} =~ m/^\d+$/) {
	$input->{objid} = $parameters->{input_contigset};
} else {
	$input->{name} = $parameters->{input_contigset};
}
my $objdatas = $ws->get_objects([$input]);
my $obj = $objdatas->[0]->{data};
my $inputgenome = {
	id => $parameters->{output_genome},
	genetic_code => $parameters->{genetic_code},
	scientific_name => $parameters->{scientific_name},
	domain => "B",
	contigs => []
};
for (my $i=0; $i < @{$obj->{contigs}}; $i++) {
	push(@{$inputgenome->{contigs}},{
		dna => $obj->{contigs}->[$i]->{sequence},
		id => $obj->{contigs}->[$i]->{id}
	});
}
my $gaserv;
if ($ARGV[2] eq "impl") {
	require "Bio/KBase/GenomeAnnotation/GenomeAnnotationImpl.pm";
	$gaserv = Bio::KBase::GenomeAnnotation::GenomeAnnotationImpl->new();
} else {
	$gaserv = Bio::KBase::GenomeAnnotation::Client->new($ARGV[2]);
}
my $workflow = {stages => []};
if (defined($parameters->{call_features_rRNA_SEED}) && $parameters->{call_features_rRNA_SEED} == 1)  {
	push(@{$workflow->{stages}},{name => "call_features_rRNA_SEED"});
}
if (defined($parameters->{call_features_tRNA_trnascan}) && $parameters->{call_features_tRNA_trnascan} == 1)  {
	push(@{$workflow->{stages}},{name => "call_features_tRNA_trnascan"});
}
if (defined($parameters->{call_selenoproteins}) && $parameters->{call_selenoproteins} == 1)  {
	push(@{$workflow->{stages}},{name => "call_selenoproteins"});
}
if (defined($parameters->{call_pyrrolysoproteins}) && $parameters->{call_pyrrolysoproteins} == 1)  {
	push(@{$workflow->{stages}},{name => "call_pyrrolysoproteins"});
}

if (defined($parameters->{call_features_repeat_region_SEED}) && $parameters->{call_features_repeat_region_SEED} == 1)  {
	push(@{$workflow->{stages}},{
		name => "call_features_repeat_region_SEED",
		"repeat_region_SEED_parameters" => {
            "min_identity" => "95",
            "min_length" => "100"
         }
	});
}
if (defined($parameters->{call_features_insertion_sequences}) && $parameters->{call_features_insertion_sequences} == 1)  {
	push(@{$workflow->{stages}},{name => "call_features_insertion_sequences"});
}
if (defined($parameters->{call_features_strep_suis_repeat}) && $parameters->{call_features_strep_suis_repeat} == 1 && $parameters->{scientific_name} =~ /^Streptococcus\s/)  {
	push(@{$workflow->{stages}},{name => "call_features_strep_suis_repeat"});
}
if (defined($parameters->{call_features_strep_pneumo_repeat}) && $parameters->{call_features_strep_pneumo_repeat} == 1 && $parameters->{scientific_name} =~ /^Streptococcus\s/)  {
	push(@{$workflow->{stages}},{name => "call_features_strep_pneumo_repeat"});
}
if (defined($parameters->{call_features_crispr}) && $parameters->{call_features_crispr} == 1)  {
	push(@{$workflow->{stages}},{name => "call_features_crispr"});
}
if (defined($parameters->{call_features_CDS_glimmer3}) && $parameters->{call_features_CDS_glimmer3} == 1)  {
	push(@{$workflow->{stages}},{
		name => "call_features_CDS_glimmer3",
		"glimmer3_parameters" => {
            "min_training_len" => "2000"
         }
	});
}
if (defined($parameters->{call_features_CDS_prodigal}) && $parameters->{call_features_CDS_prodigal} == 1)  {
	push(@{$workflow->{stages}},{name => "call_features_CDS_prodigal"});
}
if (defined($parameters->{call_features_CDS_genemark}) && $parameters->{call_features_CDS_genemark} == 1)  {
	push(@{$workflow->{stages}},{name => "call_features_CDS_genemark"});
}
my $v1flag = 0;
my $simflag = 0;
if (defined($parameters->{annotate_proteins_kmer_v2}) && $parameters->{annotate_proteins_kmer_v2} == 1)  {
	$v1flag = 1;
	$simflag = 1;
	push(@{$workflow->{stages}},{
		name => "annotate_proteins_kmer_v2",
		"kmer_v2_parameters" => {
            "min_hits" => "5"
         }
	});
}
if (defined($parameters->{kmer_v1_parameters}) && $parameters->{kmer_v1_parameters} == 1)  {
	$simflag = 1;
	push(@{$workflow->{stages}},{
		name => "annotate_proteins_kmer_v1",
		 "kmer_v1_parameters" => {
            "dataset_name" => "Release70",
            "annotate_hypothetical_only" => $v1flag
         }
	});
}
if (defined($parameters->{annotate_proteins_similarity}) && $parameters->{annotate_proteins_similarity} == 1)  {
	push(@{$workflow->{stages}},{
		name => "annotate_proteins_similarity",
		"similarity_parameters" => {
            "annotate_hypothetical_only" => $simflag
         }
	});
}
if (defined($parameters->{resolve_overlapping_features}) && $parameters->{resolve_overlapping_features} == 1)  {
	push(@{$workflow->{stages}},{
		name => "resolve_overlapping_features",
		"resolve_overlapping_features_parameters" => {}
	});
}
if (defined($parameters->{find_close_neighbors}) && $parameters->{find_close_neighbors} == 1)  {
	push(@{$workflow->{stages}},{name => "find_close_neighbors"});
}
if (defined($parameters->{call_features_prophage_phispy}) && $parameters->{call_features_prophage_phispy} == 1)  {
	push(@{$workflow->{stages}},{name => "call_features_prophage_phispy"});
}
#my $JSON = JSON->new->utf8(1);
#print STDOUT "Input genome:\n".$JSON->encode($inputgenome)."\n";
my $genome = $gaserv->run_pipeline($inputgenome, $workflow);
$genome->{gc_content} = 0.5;
if (defined($genome->{gc})) {
	$genome->{gc_content} = $genome->{gc}+0;
	delete $genome->{gc};
}
$genome->{genetic_code} = $genome->{genetic_code}+0;
if (!defined($genome->{source})) {
	$genome->{source} = "KBase";
	$genome->{source_id} = $genome->{id};
}
if (defined($genome->{contigs})) {
	my $label = "dna";
	if (defined($genome->{contigs}->[0]->{seq})) {
		$label = "seq";
	}
	$genome->{num_contigs} = @{$genome->{contigs}};
	my $sortedcontigs = [sort { $a->{$label} cmp $b->{$label} } @{$genome->{contigs}}];
	my $str = "";
	for (my $i=0; $i < @{$sortedcontigs}; $i++) {
		if (length($str) > 0) {
			$str .= ";";
		}
		$str .= $sortedcontigs->[$i]->{$label};
		
	}
	$genome->{dna_size} = length($str)+0;
	$genome->{md5} = Digest::MD5::md5_hex($str);
	$genome->{contigset_ref} = $objdatas->[0]->{info}->[6]."/".$objdatas->[0]->{info}->[0]."/".$objdatas->[0]->{info}->[4];
}
if (defined($genome->{features})) {
	for (my $i=0; $i < @{$genome->{features}}; $i++) {
		my $ftr = $genome->{features}->[$i];
		if (!defined($ftr->{type}) && $ftr->{id} =~ m/(\w+)\.\d+$/) {
			$ftr->{type} = $1;
		}
		if (defined($ftr->{protein_translation})) {
			$ftr->{protein_translation_length} = length($ftr->{protein_translation})+0;
			$ftr->{md5} = Digest::MD5::md5_hex($ftr->{protein_translation});
		}
		if (defined($ftr->{dna_sequence})) {
			$ftr->{dna_sequence_length} = length($ftr->{dna_sequence})+0;
		}
		if (defined($ftr->{quality}->{weighted_hit_count})) {
			$ftr->{quality}->{weighted_hit_count} = $ftr->{quality}->{weighted_hit_count}+0;
		}
		if (defined($ftr->{quality}->{hit_count})) {
			$ftr->{quality}->{hit_count} = $ftr->{quality}->{hit_count}+0;
		}
		if (defined($ftr->{annotations})) {
			delete $ftr->{annotations};
		}
		if (defined($ftr->{location})) {
			$ftr->{location}->[0]->[1] = $ftr->{location}->[0]->[1]+0;
			$ftr->{location}->[0]->[3] = $ftr->{location}->[0]->[3]+0;
		}
		delete $ftr->{feature_creation_event};
	}
}
delete $genome->{contigs};
delete $genome->{feature_creation_event};
delete $genome->{analysis_events};
my $object = {
	type => "KBaseGenomes.Genome",
	data => $genome,
	provenance => [{
		"time" => DateTime->now()->datetime()."+0000",
		service_ver => $gaserv->version(),
		service => "genome_annotation",
		method => "annotate_ws_contigset.pl",
		method_params => [$parameters],
		input_ws_objects => [],
		resolved_ws_objects => [],
		intermediate_incoming => [],
		intermediate_outgoing => []
	}],
};
if ($parameters->{output_genome} =~ m/^\d+$/) {
	$object->{objid} = $parameters->{output_genome};
} else {
	$object->{name} = $parameters->{output_genome};
}	
$input = {
	objects => [$object], 	
};
if ($parameters->{workspace}  =~ m/^\d+$/) {
   	$input->{id} = $parameters->{workspace};
} else {
   	$input->{workspace} = $parameters->{workspace};
}
my $output = $ws->save_objects($input);
my $JSON = JSON->new->utf8(1);
print STDOUT $JSON->encode($output)."\n";