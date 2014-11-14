package NarrativeJobService;

use strict;
use warnings;

use JSON;
use Config::Simple;
use Data::Dumper;

1;
our $version = '1.0.0';

# set object variables from ENV
sub new {
	my ($class, %h) = @_;
	if (defined($h{'shocktoken'}) && $h{'shocktoken'} eq '') {
		$h{'shocktoken'} = undef;
	}
	my $self = {
	    ws_url       => $ENV{'WS_SERVER_URL'},
		awe_url      => $ENV{'AWE_SERVER_URL'},
		shock_url	 => $ENV{'SHOCK_SERVER_URL'},
		client_group => $ENV{'AWE_CLIENT_GROUP'},
		token	     => $h{'shocktoken'}
	};
	bless $self, $class;
	$self->readConfig();
	return $self;
}

sub ws_url {
    my ($self) = @_;
    return $self->{'ws_url'};
}
sub awe_url {
    my ($self) = @_;
    return $self->{'awe_url'};
}
sub shock_url {
    my ($self) = @_;
    return $self->{'shock_url'};
}
sub client_group {
    my ($self) = @_;
    return $self->{'client_group'};
}
sub token {
    my ($self, $value) = @_;
    if (defined $value) {
        $self->{'token'} = $value;
    }
    return $self->{'token'};
}

# replace object variables from config if don't exit
sub readConfig {
    my ($self) = @_;
    # get config
    my $conf_file = $ENV{'KB_TOP'}.'/deployment.cfg';
    unless (-e $conf_file) {
        die "error: deployment.cfg not found ($conf_file)";
    }
    my $cfg_full = Config::Simple->new($conf_file);
    my $cfg = $cfg_full->param(-block=>'narrative_job_service');
    # workspace url
    unless (defined $self->{'ws_url'} && $self->{'ws_url'} ne '') {
        $self->{'ws_url'} = $cfg->{'ws-server'};
        unless (defined($self->{'ws_url'}) && $self->{'ws_url'} ne "") {
            die "ws-server not found in config";
        }
    }
    # awe url
    unless (defined $self->{'awe_url'} && $self->{'awe_url'} ne '') {
        $self->{'awe_url'} = $cfg->{'awe-server'};
        unless (defined($self->{'awe_url'}) && $self->{'awe_url'} ne "") {
            die "awe-server not found in config";
        }
    }
    # shock url
    unless (defined $self->{'shock_url'} && $self->{'shock_url'} ne '') {
        $self->{'shock_url'} = $cfg->{'shock-server'};
        unless (defined(defined $self->{'shock_url'}) && $self->{'shock_url'} ne "") {
            die "shock-server not found in config";
        }
    }
    # client group
    unless (defined $self->{'client_group'} && $self->{'client_group'} ne '') {
        $self->{'client_group'} = $cfg->{'clientgroup'};
        unless (defined($self->{'client_group'}) && $self->{'client_group'} ne "") {
            die "clientgroup not found in config";
        }
    }
}

### output ob below functions:
#{
#    string job_id;
#    string job_state;
#    string running_step_id;
#    mapping<string, string> step_outputs;
#    mapping<string, string> step_errors;
#}

sub version {
    my ($self) = @_;
    return $version;
}

sub run_app {
    my ($self, $app, $user_name) = @_;
    return {};
}

sub check_app_state {
    my ($self, $job_id) = @_;
    return {};
}

sub suspend_app {
    my ($self, $job_id) = @_;
    return {};
}

sub delete_app {
    my ($self, $job_id) = @_;
    return {};
}


