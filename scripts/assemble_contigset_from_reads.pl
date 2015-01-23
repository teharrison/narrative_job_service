#! /usr/bin/env perl

use strict;
use Carp;
use Data::Dumper;
use Getopt::Long;
use JSON;

Getopt::Long::Configure("pass_through");

my $usage = <<"End_of_Usage";

usage: $0 [ options ]

Input:

    --assembly_input   filename     - json input of KBaseAssembly.AssemblyInput typed object
    --read_library     lib          - one or more input read libraries of one of four types:
                                        KBaseAssembly.PairedEndLibrary, KBaseAssembly.SingleEndLibrary,
                                        KBaseFile.PairedEndLibrary, KBaseFile.SingleEndLibrary
    --reference        contigset    - reference contig set used for evaluating assembly quality

Output:

    --output_contigset filename     - required json output of KBaseGenomes.ContigSet typed object

Method (only one is used: pipeline > assembler > recipe):

    --assembler        string       - assembler
    --recipe           string       - assembly recipe
    --pipeline         string       - multistep assembly pipeline (e.g., "tagdust velvet")

Additional information:

    --description      text         - description of assembly job


End_of_Usage

my ($help, $assembly_input, @read_library, $reference,
    $output_contigset, $assembly_report,
    $recipe, $assembler, $pipeline,
    $description, $dry_run);

GetOptions("h|help"               => \$help,
           "i|assembly_input=s"   => \$assembly_input,
           "l|read_library=s"     => \@read_library,
           "f|reference=s"        => \$reference,
           "o|output_contigset=s" => \$output_contigset,
           "t|assembly_report=s"  => \$assembly_report,
           "r|recipe=s"           => \$recipe,
           "a|assembler=s"        => \$assembler,
           "p|pipeline=s"         => \$pipeline,
           "d|description=s"      => \$description,
           "dry"                  => \$dry_run,
	  ) or die("Error in command line arguments\n");

$help and die $usage;

($assembly_input || @read_library) && ($recipe || $assembler || $pipeline) && $output_contigset or die $usage;
$assembly_report ||= "$output_contigset.report";

verify_cmd("ar-run") and verify_cmd("ar-get");

my $method = $pipeline  ? "-p $pipeline" :
             $assembler ? "-a $assembler"  :
                          "-r $recipe";

my $ai_file = $assembly_input ? $assembly_input : libs_to_json(\@read_library, $reference);

$ai_file && -s $ai_file or die "No assembly input or read library found.\n";

my @ai_params = "--data-json $ai_file";
push @ai_params, "-m '$description'" if $description;

my $cmd = join(" ", @ai_params);

# $cmd = "ar-run $method $cmd | ar-get -w -p | fasta_to_contigset > $output_contigset";
$cmd = "ar-run $method $cmd >job 2>err";
print "$cmd\n";

exit if $dry_run;

my $rv = system($cmd);
if ($rv == 0 && -s "job") {
    system("ar-get -w -r <job >report");
    system("ar-get -w -l <job >log");
    system("ar-get -w -p <job >$output_contigset.fa");
}

if (-s "$output_contigset.fa") {
    system("fasta_to_contigset <$output_contigset.fa >$output_contigset 2>>err");
}

if ($assembly_report) {
    my $report = `cat report`;
    my $log = `cat err log`;
    my $user = $ENV{ARAST_AUTH_USER} || $ENV{KB_AUTH_USER_ID};
    my $url = $ENV{ARAST_URL};
    my $jid = `cat job`; ($jid) = $jid =~ /(\d+)/;
    my $hash = { report => $report, log => $log, user => $user, server_url => $url, job_id => $jid };
    my $s = encode_json($hash)."\n";

    my $outdir = "workspace_output";
    run("rm -rf $outdir");
    run("mkdir -p $outdir");
    print_output("KBaseAssembly.AssemblyReport", "$outdir/$assembly_report.type");
    print_output($s, "$outdir/$assembly_report.obj");
}

sub libs_to_json {
    my ($read_libs, $ref) = @_;
    $read_libs && @$read_libs or return;

    my (@pes, @ses, @ref);
    for my $json (@$read_libs) {
        my $lib = decode_json(slurp_input($json));
        if    ($lib->{handle_1}) { push @pes, $lib }     # KBaseAssembly.PairedEndLibrary
        elsif ($lib->{handle})   { push @ses, $lib }     # KBaseAssembly.SingleEndLibrary
        elsif ($lib->{lib1})     { push @pes, jgi_pe($lib) } # KBaseFile.PairedEndLibrary
        elsif ($lib->{lib})      { push @ses, jgi_se($lib) } # KBaseFile.SingleEndLibrary
        else { print STDERR "Ignored unrecognized lib: $json\n"; }
    }
    if ($ref) {
        my $r = decode_json(slurp_input($ref));
        push @ref, $r;
    }

    my $ai;
    $ai->{paired_end_libs} = \@pes if @pes;
    $ai->{single_end_libs} = \@ses if @ses;
    $ai->{references}      = \@ref if @ref;

    my $json = 'combined_reads.assembly_input';
    my $s = encode_json($ai)."\n";
    print_output($s, $json);
    return $json;
}

sub jgi_pe {
    my ($hash) = @_;
    my $base = base_from_jgi_lib($hash);
    my $lib;
    for my $key (qw(interleaved insert_size_mean insert_size_std_dev)) {
        $lib->{$key} = $hash->{$key} if $hash->{$key};
    }
    for my $i (1..2) {
        if ($hash->{"lib$i"}) {
            $lib->{"handle_$i"} = $hash->{"lib$i"}->{file};
            $lib->{"handle_$i"}->{file_name} = "$base\_$i.".$hash->{"lib$i"}->{type};
        }
    }
    return $lib;
}

sub jgi_se {
    my ($hash) = @_;
    my $base = base_from_jgi_lib($hash);
    my $lib;
    if ($hash->{"lib"}) {
        $lib->{"handle"} = $hash->{"lib"}->{file};
        $lib->{"handle"}->{file_name} = "$base.".$hash->{"lib"}->{type};
    }
    return $lib;
}

my $global_libs;
sub base_from_jgi_lib {
    my ($hash) = @_;
    my $strain = join(' ', $hash->{strain}->{genus}, $hash->{strain}->{species}, $hash->{strain}->{strain});
    my $proj   = join(' ', $hash->{source}->{source}, $hash->{source}->{project_id});
    my $base   = $strain || $proj || 'shock_reads';
    $base =~ s/\W/_/g;
    $base =~ s/_+/_/g;
    $base .= join('', '_lib', ++$global_libs);
    return $base;
}

sub parse_assembly_input {
    my ($json) = @_;
    return unless $json && -s $json;
    my $ai = decode_json(slurp_input($json));
    my @params;

    my ($pes, $ses, $ref) = ($ai->{paired_end_libs}, $ai->{single_end_libs}, $ai->{references});

    for (@$pes) { push @params, parse_pe_lib($_) }
    for (@$ses) { push @params, parse_se_lib($_) }
    for (@$ref) { push @params, parse_ref($_) }

    return @params;
}

sub parse_pe_lib {
    my ($lib) = @_;
    my @params;
    push @params, "--pair_url";
    push @params, handle_to_url($lib->{handle_1});
    push @params, handle_to_url($lib->{handle_2});
    my @ks = qw(insert_size_mean insert_size_std_dev);
    for my $k (@ks) {
        push @params, $k."=".$lib->{$k} if $lib->{$k};
    }
    return @params;
}

sub parse_se_lib {
    my ($lib) = @_;
    my @params;
    push @params, "--single_url";
    push @params, handle_to_url($lib->{handle});
    return @params;
}

sub parse_ref {
    my ($ref) = @_;
    my @params;
    push @params, "--reference_url";
    push @params, handle_to_url($ref->{handle});
    return @params;
}

sub handle_to_url {
    my ($h) = @_;
    my $url = sprintf "'%s/node/%s?download'", $h->{url}, $h->{id};
}

sub verify_cmd {
    my ($cmd) = @_;
    system("which $cmd >/dev/null") == 0 or die "Command not found: $cmd\n";
}

#-----------------------------------------------------------------------------
#  Read the entire contents of a file or stream into a string.  This command
#  if similar to $string = join( '', <FH> ), but reads the input by blocks.
#
#     $string = slurp_input( )                 # \*STDIN
#     $string = slurp_input(  $filename )
#     $string = slurp_input( \*FILEHANDLE )
#
#-----------------------------------------------------------------------------
sub slurp_input
{
    my $file = shift;
    my ( $fh, $close );
    if ( ref $file eq 'GLOB' )
    {
        $fh = $file;
    }
    elsif ( $file )
    {
        if    ( -f $file )                    { $file = "<$file" }
        elsif ( $_[0] =~ /^<(.*)$/ && -f $1 ) { }  # Explicit read
        else                                  { return undef }
        open $fh, $file or return undef;
        $close = 1;
    }
    else
    {
        $fh = \*STDIN;
    }

    my $out =      '';
    my $inc = 1048576;
    my $end =       0;
    my $read;
    while ( $read = read( $fh, $out, $inc, $end ) ) { $end += $read }
    close $fh if $close;

    $out;
}

#-----------------------------------------------------------------------------
#  Print text to a file.
#
#     print_output( $string )                 # \*STDIN
#     print_output( $string, $filename )
#     print_output( $string, \*FILEHANDLE )
#
#-----------------------------------------------------------------------------
sub print_output
{
    my ($text, $file) = @_;

    #  Null string or undef
    print $text if ( ! defined( $file ) || ( $file eq "" ) );

    #  FILEHANDLE
    print $file, $text if ( ref( $file ) eq "GLOB" );

    #  Some other kind of reference; return the unused value
    return if ref( $file );

    #  File name
    my $fh;
    open( $fh, '>', $file ) || die "Could not open output $file\n";
    print $fh $text;
    close( $fh );
}

sub run { system(@_) == 0 or confess("FAILED: ". join(" ", @_)); }
