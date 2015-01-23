#! /usr/bin/env perl

use strict;
use Data::Dumper;
use Digest::MD5;
use JSON;

my $usage = "Usage: $0 [name] < input.fasta > contigset.json \n\n";

my $name = shift @ARGV || 'assembled_contigs';

my @seqs = read_fasta();

my @contigs = map { { id => $_->[0],
                      description => $_->[1],
                      sequence => $_->[2],
                      length => length($_->[2]),
                      md5 => Digest::MD5::md5_hex($_->[2]) }
                  } @seqs;

my $md5 = md5_for_seqs(\@seqs);

my $id = "kb|contigset.999999"; # TODO: call id server; but this appears unused anyway

my $obj = { contigs => \@contigs,
            id => $id,
            md5 => $md5,
            name => $name,
            type => "Organism",
            source => "KBase",
            source_id => $id
          };

print encode_json($obj)."\n";

sub md5_for_seqs {
    my ($seqs) = @_;
    my @seqs = sort map { $_->[2] } @$seqs;
    my $concat = join(";", @seqs);
    Digest::MD5::md5_hex($concat);
}

sub read_fasta
{
     my $dataR = ( $_[0] && ref $_[0] eq 'SCALAR' ) ?  $_[0] : slurp( @_ );
    $dataR && $$dataR or return wantarray ? () : [];

    my $is_fasta = $$dataR =~ m/^[\s\r]*>/ or die "No valid contigs found\n";

    my @seqs = map { $_->[2] =~ tr/ \n\r\t//d; $_ }
               map { /^(\S+)([ \t]+([^\n\r]+)?)?[\n\r]+(.*)$/s ? [ $1, $3 || '', $4 || '' ] : () }
               split /[\n\r]+>[ \t]*/m, $$dataR;

    #  Fix the first sequence, if necessary
    if ( @seqs )
    {
        if ( $is_fasta )
        {
            $seqs[0]->[0] =~ s/^>//;  # remove > if present
        }
        elsif ( @seqs == 1 )
        {
            $seqs[0]->[1] =~ s/\s+//g;
            @{ $seqs[0] } = ( 'raw_seq', '', join( '', @{$seqs[0]} ) );
        }
        else  #  First sequence is not fasta, but others are!  Throw it away.
        {
            shift @seqs;
        }
    }

    wantarray() ? @seqs : \@seqs;
}

sub slurp
{
    my ( $fh, $close );
    if ( $_[0] && ref $_[0] eq 'GLOB' )
    {
        $fh = shift;
    }
    elsif ( $_[0] && ! ref $_[0] )
    {
        my $file = shift;
        if    ( -f $file                       ) { }
        elsif (    $file =~ /^<(.*)$/ && -f $1 ) { $file = $1 }  # Explicit read
        else                                     { return undef }
        open( $fh, '<', $file ) or return undef;
        $close = 1;
    }
    else
    {
        $fh = \*STDIN;
        $close = 0;
    }

    my $out = '';
    my $inc = 1048576;
    my $end =       0;
    my $read;
    while ( $read = read( $fh, $out, $inc, $end ) ) { $end += $read }
    close( $fh ) if $close;

    \$out;
}
