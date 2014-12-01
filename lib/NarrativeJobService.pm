package NarrativeJobService;

use strict;
use warnings;

use JSON;
use Template;
use LWP::UserAgent;
use HTTP::Request::Common;
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
		generic_wrapper  => undef,
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
sub generic_wrapper {
    my ($self) = @_;
    return $self->{'generic_wrapper'};
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
        die "[config error] deployment.cfg not found ($conf_file):";
    }
    my $cfg_full = Config::Simple->new($conf_file);
    my $cfg = $cfg_full->param(-block=>'narrative_job_service');
    # get values
    foreach my $val (('ws_url', 'awe_url', 'shock_url', 'client_group', 'script_wrapper', 'generic_wrapper')) {
        unless (defined $self->{$val} && $self->{$val} ne '') {
            $self->{$val} = $cfg->{$val};
            unless (defined($self->{$val}) && $self->{$val} ne "") {
                die "[config error] '$val' not found in deployment.cfg:";
            }
        }
    }
    # get service wrapper info
    my @services = @{$cfg->{'supported_services'}};
    my @wrappers = @{$cfg->{'service_wrappers'}};
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
    # get workflow
    my $workflow = $self->compose_app($app, $user_name);
    # submit workflow
    my $job = $self->_post_awe_workflow($workflow);
    # return app info
    return $self->check_app_state(undef, $job);
}

sub compose_app {
    my ($self, $app, $user_name) = @_;

    my $tpage = Template->new(ABSOLUTE => 1);
    # build info
    my $info_vars = {
        app_name     => $app->{name},
        user_id      => $user_name,
        client_group => $self->client_group
    };
    
    my $info_temp = _info_template();
    my $info_str  = "";
    $tpage->process(\$info_temp, $info_vars, \$info_str) || die "[template error] ".$tpage->error().":";
    # start workflow
    my $workflow = {
        info => $self->json->decode($info_str),
        tasks => []
    };
    
    # build tasks
    my $tnum = 0;
    foreach my $step (@{$app->{steps}}) {
        # check type
        unless (($step->{type} eq 'script') || ($step->{type} eq 'service')) {
            die "[step error] invalid step type '".$step->{type}."' for ".$step->{step_id}.":";
        }
        my $service = $step->{$step->{type}};
        
        # task templating
        my $task_vars = {
            cmd_name   => "",
            arg_list   => "",
            kb_service => $service->{service_name},
            kb_method  => $service->{method_name},
            kb_type    => $step->{type},
            user_token => $self->token,
            user_id    => $user_name,
            shock_url  => $self->shock_url,
            step_id    => $step->{step_id},
            # for now just the previous task
            depends_on => ($tnum > 0) ? '"'.($tnum-1).'"' : "",
            this_task  => $tnum,
            inputs     => ""
        };
        # shock input attr
        my $in_attr = {
            type        => "kbase_app",
            app         => $app->{name},
            user        => $user_name,
            step        => $step->{step_id},
            service     => $service->{service_name},
            method      => $service->{method_name},
            method_type => $step->{type},
            data_type   => "input",
            format      => "json"
        };
        
        # service step
        if ($step->{type} eq 'service') {
            my $script_name = $self->generic_wrapper;
            # get custom wrapper if available
            if (exists $self->service_wrappers->{$service->{service_name}}) {
                $script_name = $self->service_wrappers->{$service->{service_name}};
            }
            my $fname = 'parameters.json';
            my $arg_array  = $self->_process_args($step->{parameters});
            my $input_hash = $self->_post_shock_file($in_attr, $arg_array, $fname);
            $task_vars->{inputs}   = '"inputs": '.$self->json->encode($input_hash).",\n";
            $task_vars->{cmd_name} = $self->service_wrappers->{$service->{service_name}};
            $task_vars->{arg_list} = $service->{method_name}." @".$fname." ".$service->{service_url};
        }
        # script step
        elsif ($step->{type} eq 'script') {
            # use wrapper
            if ($service->{has_files}) {
                my $fname = 'parameters.json';
                my $arg_min = $self->_minify_args($step->{parameters});
                my $input_hash = $self->_post_shock_file($in_attr, $arg_min, $fname);
                $task_vars->{inputs}   = '"inputs": '.$self->json->encode($input_hash).",\n";
                $task_vars->{cmd_name} = $self->script_wrapper;
                $task_vars->{arg_list} = "--params @".$fname." ".$service->{method_name};
            }
            # run given cmd
            else {
                my $arg_str = $self->_stringify_args($step->{parameters});
                $task_vars->{cmd_name} = $service->{method_name};
                $task_vars->{arg_list} = $arg_str;
            }
        }
        # process template / add to workflow
        my $task_temp = _task_template();
        my $task_str  = "";
        $tpage->process(\$task_temp, $task_vars, \$task_str) || die "[template error] ".$tpage->error().":";
        $workflow->{tasks}->[$tnum] = $self->json->decode($task_str);
        $tnum += 1;
    }
    # return workflow string
    return $self->json->encode($workflow);
}

sub check_app_state {
    my ($self, $job_id, $job) = @_;
    
    # get job doc
    unless ($job && ref($job)) {
        $job = $self->_awe_action('job', $job_id, 'get');
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
    # assume each task has 1 workunit
    foreach my $task (@{$job->{tasks}}) {
        my $step_id = $task->{userattr}->{step};
        # get running
        if (($task->{state} eq 'queued') || ($task->{state} eq 'in-progress')) {
            $output->{running_step_id} = $step_id;
        }
        # get stdout text
        my $stdout = "";
        if (exists($task->{outputs}{'awe_stdout.txt'}) && $task->{outputs}{'awe_stdout.txt'}{url}) {
            $stdout = $self->_get_shock_file($task->{outputs}{'awe_stdout.txt'}{url});
        } else {
            $stdout = $self->_awe_action('work', $task->{taskid}.'_0', 'get', 'report=stdout');
        }
        if ($stdout) {
            $output->{step_outputs}{$step_id} = $stdout;
        }
        # get stderr text
        my $stderr = "";
        if (exists($task->{outputs}{'awe_stderr.txt'}) && $task->{outputs}{'awe_stderr.txt'}{url}) {
            $stderr = $self->_get_shock_file($task->{outputs}{'awe_stderr.txt'}{url});
        } else {
            $stderr = $self->_awe_action('work', $task->{taskid}.'_0', 'get', 'report=stderr');
        }
        if ($stderr) {
            $output->{step_errors}{$step_id} = $stderr;
        }
    }
    return $output;
}

sub suspend_app {
    my ($self, $job_id) = @_;
    my $result = $self->_awe_action('job', $job_id, 'put', 'suspend');
    return ($result =~ /^job suspended/) ? "success" : "failure";
}

sub resume_app {
    my ($self, $job_id) = @_;
    my $result = $self->_awe_action('job', $job_id, 'put', 'resume');
    return ($result =~ /^job resumed/) ? "success" : "failure";
}

sub delete_app {
    my ($self, $job_id) = @_;
    my $result = $self->_awe_action('job', $job_id, 'delete');
    return ($result =~ /^job deleted/) ? "success" : "failure";
}

sub list_config {
    my ($self) = @_;
    my $cfg = {
        ws_url    => $self->ws_url,
		awe_url   => $self->awe_url,
		shock_url => $self->shock_url,
		client_group   => $self->client_group,
		script_wrapper => $self->script_wrapper
    };
    foreach my $s (keys %{$self->service_wrappers}) {
        $cfg->{$s} = $self->service_wrappers->{$s};
    }
    return $cfg;
}

sub _awe_action {
    my ($self, $type, $id, $action, $options) = @_;

    my $response = undef;
    my $url = $self->awe_url.'/'.$type.'/'.$id;
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
        if ((! $@) || ($@ =~ /malformed JSON string/)) {
            die "[awe error] unable to connect to AWE server:"
        } else {
            die "[awe error] ".$@.":";
        }
    } elsif (exists($response->{error}) && $response->{error}) {        
        my $err = $response->{error}[0];
        # special exception for empty stdout / stderr
        if ($err =~ /^log type .* not found$/) {
            return "";
        }
        # make message more useful
        elsif ($err eq "Not Found") {
            $err = "$type $id does not exist";
        }
        die "[awe error] ".$err.":";
    } else {
        return $response->{data};
    }
}

sub _post_awe_workflow {
    my ($self, $workflow) = @_;

    my $response = undef;
    my $content  = { upload => [undef, "kbase_app.awf", Content => $workflow] };
    my @args = (
        'Authorization', 'OAuth '.$self->token,
        'Datatoken', $self->token,
        'Content_Type', 'multipart/form-data',
        'Content', $content
    );
    
    eval {
        my $post = $self->agent->post($self->awe_url.'/job', @args);
        $response = $self->json->decode( $post->content );
    };
    
    if ($@ || (! $response)) {
        if ((! $@) || ($@ =~ /malformed JSON string/)) {
            die "[awe error] unable to connect to AWE server:"
        } else {
            die "[awe error] ".$@.":";
        }
    } elsif (exists($response->{error}) && $response->{error}) {
        die "[awe error] ".$response->{error}[0].":";
    } else {
        return $response->{data};
    }
}

sub _get_shock_file {
    my ($self, $url) = @_;
    
    my $response = undef;
    eval {
        $response = $self->agent->get($url, 'Authorization', 'OAuth '.$self->token);
    };
    if ($@ || (! $response)) {
        die "[shock error] ".($@ || "unable to connect to Shock server").":";
    }
    
    # if return is json encoded get error
    eval {
        my $json = $self->json->decode( $response->content );
        if (exists($json->{error}) && $json->{error}) {
            die "[shock error] ".$json->{error}[0].":";
        }
    };
    # get content
    return $response->content;
}

sub _post_shock_file {
    my ($self, $attr, $data, $fname) = @_;
    
    my $response = undef;
    my $content  = {
        upload => [undef, $fname, Content => $self->json->encode($data)],
        attributes => [undef, "$fname.json", Content => $self->json->encode($attr)]
    };
    my @args = (
        'Authorization', 'OAuth '.$self->token,
        'Content_Type', 'multipart/form-data',
        'Content', $content
    );
    
    eval {
        my $post = $self->agent->post($self->shock_url.'/node', @args);
        $response = $self->json->decode( $post->content );
    };
    
    if ($@ || (! $response)) {
        if ((! $@) || ($@ =~ /malformed JSON string/)) {
            die "[shock error] unable to connect to Shock server:"
        } else {
            die "[shock error] ".$@.":";
        }
    } elsif (exists($response->{error}) && $response->{error}) {
        die "[shock error] ".$response->{error}[0].":";
    } else {
        return {
            $fname => {
                host => $self->shock_url,
                node => $response->{data}{id}
            }
        };
    }
}

sub _process_args {
    my ($self, $params) = @_;
    my $arg_array = [];
    for (my $i=0; $i<@$params; $i++) {
        my $p = $params->[$i];
        eval {
            if ($p->{type} eq 'string') {
                push @$arg_array, $p->{value};
            } elsif ($p->{type} eq 'int') {
                push @$arg_array, int($p->{value});
            } elsif ($p->{type} eq 'float') {
                push @$arg_array, ($p->{value} * 1.0);
            } elsif ($p->{type} eq 'object') {
                push @$arg_array, $self->json->decode($p->{value});
            }
        };
        if ($@) {
            die "[step error] parameter number ".$i." is not valid, value is not of type '".$p->{type}."':";
        }
    }
    return $arg_array;
}

sub _minify_args {
    my ($self, $params) = @_;
    my $arg_min = [];
    for (my $i=0; $i<@$params; $i++) {
        my $p = $params->[$i];
        $arg_min->[$i] = {
            label           => $p->{label},
            value           => $p->{value},
            is_workspace_id => $p->{is_workspace_id},
            is_input        => $p->{ws_object}{is_input},
            workspace_name  => $p->{ws_object}{workspace_name},
            object_type     => $p->{ws_object}{object_type}
        };
    }
    return $arg_min;
}

sub _stringify_args {
    my ($self, $params) = @_;
    my @arg_list = ();
    for (my $i=0; $i<@$params; $i++) {
        my $p = $params->[$i];
        if ($p->{label} =~ /\s/) {
            die "[step error] parameter number ".$i." is not valid, label '".$p->{label}."' may not contain whitspace:";
        }
        # short option
        elsif (length($p->{label}) == 1) {
            push @arg_list, "-".$p->{label};
        }
        # long option
        elsif (length($p->{label}) > 1) {
            push @arg_list, "--".$p->{label};
        }
        # has value
        if ($p->{value}) {
            push @arg_list, $p->{value};
        }
    }
    return join(" ", @arg_list);
}

sub _info_template {
    return qq(
    {
        "pipeline": "narrative_job_service",
        "name": "[% app_name %]",
        "user": "[% user_id %]",
        "clientgroups": "[% client_group %]",
        "noretry": true,
        "userattr": {
            "type": "kbase_app",
            "app": "[% app_name %]",
            "user": "[% user_id %]"
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
                    "KB_AUTH_TOKEN": "[% user_token %]",
                    "KB_AUTH_USER_ID": "[% user_id %]"
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
            "data_type": "output",
            "format": "text"
        },
        "taskid": "[% this_task %]",
        "totalwork": 1
    });
}

