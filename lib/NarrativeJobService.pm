package NarrativeJobService;

use strict;
use warnings;

use JSON;
use Config::Simple;
use Data::Dumper;

1;

# set object variables from ENV
sub new {
	my ($class, %h) = @_;
	my $self = {
	    ws_url        => $ENV{'WS_SERVER_URL'},
		awe_url       => $ENV{'AWE_SERVER_URL'},
		shock_url	  => $ENV{'SHOCK_SERVER_URL'},
		client_group  => $ENV{'AWE_CLIENT_GROUP'},
		ws_wrapper    => undef,
		api_wrapper   => undef,
		user_token	  => undef,
		service_token => undef
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
sub ws_wrapper {
    my ($self) = @_;
    return $self->{'ws_wrapper'};
}
sub api_wrapper {
    my ($self) = @_;
    return $self->{'api_wrapper'};
}
sub user_token {
    my ($self, $value) = @_;
    if (defined $value) {
        $self->{'user_token'} = $value;
    }
    return $self->{'user_token'};
}
sub service_token {
    my ($self, $value) = @_;
    if (defined $value) {
        $self->{'service_token'} = $value;
    }
    return $self->{'service_token'};
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
    # get values
    foreach my $val (('ws_url','awe_url','shock_url','client_group','ws_wrapper','api_wrapper','service_token')) {
        unless (defined $self->{$val} && $self->{$val} ne '') {
            $self->{$val} = $cfg->{$val};
            unless (defined($self->{$val}) && $self->{$val} ne "") {
                die "$val not found in config";
            }
        }
    }
}

### output of below functions:
#{
#    string job_id;
#    string job_state;
#    string running_step_id;
#    mapping<string, string> step_outputs;
#    mapping<string, string> step_errors;
#}

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

