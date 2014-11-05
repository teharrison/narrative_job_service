#!/usr/bin/env perl
use strict;
use warnings;


require Bio::KBase::NarrativeJobService::Client;

my $njs_obj = new Bio::KBase::NarrativeJobService::Client();
my $status = $njs_obj->hello() || 'undefined';

print "hello ".$status."\n";



