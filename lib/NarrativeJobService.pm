package NarrativeJobService;

use strict;
use warnings;

use JSON;
use Template;
use LWP::UserAgent;
use Config::Simple;
use Data::Dumper;

1;

# set object variables from ENV
sub new {
	my ($class) = @_;

	my $agent = LWP::UserAgent->new;
	my $json  = JSON->new;
    $json = $json->utf8();
    $json->max_size(0);
    $json->allow_nonref;

	my $self = {
	    agent     => $agent,
	    json      => $json,
	    token	  => undef,
	    ws_url    => $ENV{'WS_SERVER_URL'},
		awe_url   => $ENV{'AWE_SERVER_URL'},
		shock_url => $ENV{'SHOCK_SERVER_URL'},
		client_group     => $ENV{'AWE_CLIENT_GROUP'},
		script_wrapper   => undef,
		service_wrappers => {},
	};

	bless $self, $class;
	$self->readConfig();
	return $self;
}

sub agent {
    my ($self) = @_;
    return $self->{'agent'};
}
sub json {
    my ($self) = @_;
    return $self->{'json'};
}
sub token {
    my ($self, $value) = @_;
    if (defined $value) {
        $self->{'token'} = $value;
    }
    return $self->{'token'};
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
sub script_wrapper {
    my ($self) = @_;
    return $self->{'script_wrapper'};
}
sub service_wrappers {
    my ($self) = @_;
    return $self->{'service_wrappers'};
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
    foreach my $val (('ws_url', 'awe_url', 'shock_url', 'client_group', 'script_wrapper')) {
        unless (defined $self->{$val} && $self->{$val} ne '') {
            $self->{$val} = $cfg->{$val};
            unless (defined($self->{$val}) && $self->{$val} ne "") {
                die "$val not found in config";
            }
        }
    }
    # get service wrapper info
    my @services = split(/,/, $cfg->{'supported_services'});
    my @wrappers = split(/,/, $cfg->{'service_wrappers'});
    for (my $i=0; $i<@services; $i++) {
        $self->{'service_wrappers'}->{$services[$i]} = $wrappers[$i];
    }
}

### output of run_app, check_app_state:
#{
#    string job_id;
#    string job_state;
#    string running_step_id;
#    mapping<string, string> step_outputs;
#    mapping<string, string> step_errors;
#}

sub run_app {
    my ($self, $app, $user_name) = @_;

    my $tpage = Template->new(ABSOLUTE => 1);
    # build info
    my $info_str  = "";
    my $info_temp = _info_template();
    my $info_vars = {
        app_name     => $app->{name},
        user_id      => $user_name,
        client_group => $self->client_group
    };
    $tpage->process(\$info_temp, $info_vars, \$info_str) || return ({}, $tpage->error());
    # start workflow
    my $workflow = {
        info => $self->json->decode($info_str),
        tasks => []
    };
    # build tasks
    my $tnum = 0;
    foreach my $step (@{$app->{steps}}) {
        # error checking of step type and service name
        unless (($step->{type} eq 'script') || ($step->{type} eq 'service')) {
            return ({}, "[error] invalid step type '".$step->{type}."' for ".$step->{step_id});
        }
        my $service_info = $step->{$step->{type}};
        if (($step->{type} eq 'service') && (! exists($self->service_wrappers->{$service_info->{service_name}}))) {
            return ({}, "[error] unsupported service '".$service_info->{service_name}."' for ".$step->{step_id});
        }
        # task templating
        my $step_str  = "";
        my $step_temp = _info_template();
        my $step_vars = {
            cmd_name   => "",
            arg_list   => "",
            kb_service => $service_info->{service_name},
            kb_method  => $service_info->{method_name},
            kb_type    => $step->{type},
            user_token => $self->token,
            shock_url  => $self->shock_url,
            step_id    => $step->{step_id},
            # for now just the previous task
            depends_on => ($tnum > 0) ? '"'.($tnum-1).'"' : "",
            this_task  => $tnum,
            inputs     => ""
        };

        $tnum += 1;
    }

    return ({}, undef);
}

sub check_app_state {
    my ($self, $job_id) = @_;
    # get job doc
    my ($job, $err) = $self->_awe_job_action($job_id, 'get');
    if ($err) {
        return ({}, $err);
    }
    # set output
    my $output = {
        job_id          => $job->{id},
        job_state       => $job->{state},
        running_step_id => "",
        step_outputs    => {},
        step_errors     => {}
    };
    # parse each task
    foreach my $task (@{$job->{tasks}}) {
        my $step_id = $task->{userattr}->{step};
        # get running
        if (($task->{state} eq 'queued') || ($task->{state} eq 'in-progress')) {
            $output->{running_step_id} = $step_id;
        }
        # get stdout text
        if (exists($task->{outputs}{'awe_stdout.txt'}) && $task->{outputs}{'awe_stdout.txt'}{url}) {
            my ($content, $err) = $self->_shock_node_file($task->{outputs}{'awe_stdout.txt'}{url});
            if ($err) {
                return ({}, $err);
            }
            $output->{step_outputs}{$step_id} = $content;
        }
        # get stderr text
        if (exists($task->{outputs}{'awe_stderr.txt'}) && $task->{outputs}{'awe_stderr.txt'}{url}) {
            my ($content, $err) = $self->_shock_node_file($task->{outputs}{'awe_stderr.txt'}{url});
            if ($err) {
                return ({}, $err);
            }
            $output->{step_errors}{$step_id} = $content;
        }
    }
    return ($output, undef);
}

sub suspend_app {
    my ($self, $job_id) = @_;
    my ($result, $err) = $self->_awe_job_action($job_id, 'put', 'suspend');
    if ($err) {
        return ("", $err);
    } elsif ($result =~ /^job suspended/) {
        return ("success", undef);
    } else {
        return ("failure", undef);
    }
}

sub resume_app {
    my ($self, $job_id) = @_;
    my ($result, $err) = $self->_awe_job_action($job_id, 'put', 'resume');
    if ($err) {
        return ("", $err);
    } elsif ($result =~ /^job resumed/) {
        return ("success", undef);
    } else {
        return ("failure", undef);
    }
}

sub delete_app {
    my ($self, $job_id) = @_;
    my ($result, $err) = $self->_awe_job_action($job_id, 'delete');
    if ($err) {
        return ("", $err);
    } elsif ($result =~ /^job deleted/) {
        return ("success", undef);
    } else {
        return ("failure", undef);
    }
}

# returns: (data, err_msg)
sub _awe_job_action {
    my ($self, $job_id, $action, $options) = @_;

    my $response = undef;
    my $url = $self->awe_url.'/job/'.$job_id;
    if ($options) {
        $url .= "?".$options;
    }
    my @args = ('Authorization', 'OAuth '.$self->token);

    eval {
        my $tmp = undef;
        if ($action eq 'delete') {
            $tmp = $self->agent->delete($url, @args);
        } elsif ($action eq 'put') {
            my $req = POST($url, @args);
            $req->method('PUT');
            $tmp = $self->agent->request($req);
        } elsif ($action eq 'get') {
            $tmp = $self->agent->get($url, @args);
        }
        $response = $self->json->decode( $tmp->content );
    };

    if ($@ || (! ref($response))) {
        return ({}, $@ || "Unable to connect to AWE server");
    } elsif (exists($response->{error}) && $response->{error}) {
        my $err = $response->{error}[0];
        if ($err eq "Not Found") {
            $err = "Job $job_id does not exist";
        }
        return ({}, $err);
    } else {
        return ($response->{data}, undef);
    }
}

# returns: (node_file_str, err_msg)
sub _shock_node_file {
    my ($self, $url) = @_;

    my $response = undef;
    eval {
        $response = $self->agent->get($url, 'Authorization', 'OAuth '.$self->token);
    };
    if ($@ || (! $response)) {
        return ("", $@ || "Unable to connect to Shock server");
    }
    # if return is json encoded get error
    eval {
        my $json = $self->json->decode( $response->content );
        if (exists($json->{error}) && $json->{error}) {
            return ("", $json->{error});
        }
    };
    # get content
    return ($response->content, undef);
}

sub _info_template {
    return qq(
    "info": {
        "pipeline": "narrative_job_service",
        "name": [% app_name %],
        "user": [% user_id %],
        "clientgroups": "[% client_group %]",
        "userattr": {
            "type": "kbase_app",
            "app": [% app_name %],
            "user": [% user_id %]
        }
    });
}

sub _task_template {
    return qq(
    {
        "cmd": {
            "name": "[% cmd_name %]",
            "args": "[% arg_list %]",
            "description": "[% kb_service %].[% kb_method %]",
            "environ": {
                "private": {
                    "KB_AUTH_TOKEN": "[% user_token %]"
                }
            }
        },
        "dependsOn": [[% dependent_tasks %]],
        [% inputs %]
        "outputs": {
            "awe_stdout.txt": {
                "host": "[% shock_url %]",
                "node": "-",
                "attrfile": "userattr.json"
            },
            "awe_stderr.txt": {
                "host": "[% shock_url %]",
                "node": "-",
                "attrfile": "userattr.json"
            }
        },
        "userattr": {
            "step": "[% step_id %]",
            "service": "[% kb_service %]",
            "method": "[% kb_method %]",
            "method_type": "[% kb_type %]",
            "data_type": "shell output",
            "format": "text"
        },
        "taskid": "[% this_task %]",
        "totalwork": 1
    });
}

