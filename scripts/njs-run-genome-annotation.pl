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
use Getopt::Long;
use Bio::KBase::GenomeAnnotation::Client;
use Bio::KBase::workspace::ScriptHelpers qw(get_ws_client workspace workspaceURL parseObjectMeta parseWorkspaceMeta printObjectMeta);

#Defining globals describing behavior
my $command     = "annotate_genome";
my $param_file  = "parameters.json";
my $service_url = "http://tutorial.theseed.org/services/genome_annotation";
my $ws_url  = "http://kbase.us/services/ws";
my $help    = 0;
my $usage   = "Usage:\nnjs-run-genome-annotation --command <Command name> --param_file <Parameters file> --service_url <Service URL> --ws_url <Workspace URL>\n";
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
if ($command ne "annotate_genome") {
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

#Retrieving service client or server object
my $ws = get_ws_client($ws_url);
my $input = {};
if ($parameters->{workspace} =~ m/^\d+$/) {
	$input->{wsid} = $parameters->{workspace};
} else {
	$input->{workspace} = $parameters->{workspace};
}
my $inputgenome;
my $contigsetref;
my $oldfunchash = {};
if (defined($parameters->{input_genome})) {
	if ($parameters->{input_genome} =~ m/^\d+$/) {
		$input->{objid} = $parameters->{input_genome};
	} else {
		$input->{name} = $parameters->{input_genome};
	}
	my $objdatas = $ws->get_objects([$input]);
	$inputgenome = $objdatas->[0]->{data};
	if (defined($inputgenome->{contigset_ref}) && $inputgenome->{contigset_ref} =~ m/^([^\/]+)\/([^\/]+)/) {
		$contigsetref = $inputgenome->{contigset_ref};
		my $contigws = $1;
		$parameters->{input_contigset} = $2;
		$input = {};
		if ($contigws =~ m/^\d+$/) {
			$input->{wsid} = $contigws;
		} else {
			$input->{workspace} = $contigws;
		}
	}
	for (my $i=0; $i < @{$inputgenome->{features}}; $i++) {
		if (lc($inputgenome->{features}->[$i]->{type}) eq "cds" || lc($inputgenome->{features}->[$i]->{type}) eq "peg") {
			$oldfunchash->{$inputgenome->{features}->[$i]->{id}} = $inputgenome->{features}->[$i]->{function};
			$inputgenome->{features}->[$i]->{function} = "hypothetical protein";
		}
	}
	$parameters->{genetic_code} = $inputgenome->{genetic_code};
	$parameters->{domain} = $inputgenome->{domain};
	$parameters->{scientific_name} = $inputgenome->{scientific_name};
} else {
	$inputgenome = {
		id => $parameters->{output_genome},
		genetic_code => $parameters->{genetic_code},
		scientific_name => $parameters->{scientific_name},
		domain => $parameters->{domain},
		contigs => []
	};
}
if (defined($parameters->{input_contigset})) {
	if ($parameters->{input_contigset} =~ m/^\d+$/) {
		$input->{objid} = $parameters->{input_contigset};
	} else {
		$input->{name} = $parameters->{input_contigset};
	}
	my $objdatas = $ws->get_objects([$input]);
	my $obj = $objdatas->[0]->{data};
	for (my $i=0; $i < @{$obj->{contigs}}; $i++) {
		push(@{$inputgenome->{contigs}},{
			dna => $obj->{contigs}->[$i]->{sequence},
			id => $obj->{contigs}->[$i]->{id}
		});
	}
	$contigsetref = $objdatas->[0]->{info}->[6]."/".$objdatas->[0]->{info}->[0]."/".$objdatas->[0]->{info}->[4];	
}elsif(!defined($inputgenome->{contigs})){
    $inputgenome->{contigs} = [];
}
my $gaserv;
if ($service_url eq "impl") {
	require "Bio/KBase/GenomeAnnotation/GenomeAnnotationImpl.pm";
	$gaserv = Bio::KBase::GenomeAnnotation::GenomeAnnotationImpl->new();
} else {
	$gaserv = Bio::KBase::GenomeAnnotation::Client->new($service_url);
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
            "min_hits" => "5",
            "annotate_hypothetical_only" => 1
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
if ( defined($genome->{contigs}) && scalar(@{$genome->{contigs}})>0 ) {
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
	$genome->{contigset_ref} = $contigsetref;
}
if (defined($genome->{features})) {
	for (my $i=0; $i < @{$genome->{features}}; $i++) {
		my $ftr = $genome->{features}->[$i];
		if (defined($oldfunchash->{$ftr->{id}}) && (!defined($ftr->{function}) || $ftr->{function} =~ /hypothetical\sprotein/)) {
			if (defined($parameters->{retain_old_anno_for_hypotheticals}) && $parameters->{retain_old_anno_for_hypotheticals} == 1)  {
				$ftr->{function} = $oldfunchash->{$ftr->{id}};
			}
		}
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
