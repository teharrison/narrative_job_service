package NarrativeJobService;

use strict;
use warnings;

use JSON;
use Template;
use LWP::UserAgent;
use HTTP::Request::Common;
use Config::Simple;
use Data::Dumper;
use POSIX qw(strftime);

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
	    log_dir   => ".",
	    ws_url    => $ENV{'WS_SERVER_URL'},
		awe_url   => $ENV{'AWE_SERVER_URL'},
		shock_url => $ENV{'SHOCK_SERVER_URL'},
		client_group       => $ENV{'AWE_CLIENT_GROUP'},
		client_group_map   => {},
		script_wrapper     => undef,
		service_wrappers   => {},
		service_auth_name  => "",
		service_auth_token => ""
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
sub log_dir {
    my ($self) = @_;
    return $self->{'log_dir'};
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
sub client_group_map {
    my ($self) = @_;
    return $self->{'client_group_map'};
}
sub script_wrapper {
    my ($self) = @_;
    return $self->{'script_wrapper'};
}
sub service_wrappers {
    my ($self) = @_;
    return $self->{'service_wrappers'};
}
sub service_auth_name {
    my ($self) = @_;
    return $self->{'service_auth_name'};
}
sub service_auth_token {
    my ($self) = @_;
    return $self->{'service_auth_token'};
}

# replace object variables from config if don't exit
sub readConfig {
    my ($self) = @_;
    # get config
    my $conf_file = $ENV{'KB_TOP'}.'/deployment.cfg';
    unless (-e $conf_file) {
        print STDERR "[config error] deployment.cfg not found ($conf_file)\n";
        die "[config error] deployment.cfg not found ($conf_file):";
    }
    my $cfg_full = Config::Simple->new($conf_file);
    my $cfg = $cfg_full->param(-block=>'narrative_job_service');
    # get values
    foreach my $val (('ws_url', 'awe_url', 'shock_url', 'client_group', 'script_wrapper', 'service_auth_name', 'service_auth_token')) {
        unless (defined $self->{$val} && $self->{$val} ne '') {
            $self->{$val} = $cfg->{$val};
            unless (defined($self->{$val}) && $self->{$val} ne "") {
                print STDERR "[config error] '$val' not found in deployment.cfg\n";
                die "[config error] '$val' not found in deployment.cfg:";
            }
        }
    }
    # set log dir
    if ($cfg->{'log_dir'}) {
        $self->{'log_dir'} = $cfg->{'log_dir'};
        unless (-d $self->{'log_dir'}."/log") {
            mkdir($self->{'log_dir'}."/log");
        }
    }
    # client group mapping
    if (exists($cfg->{'client_group_map'}) && (scalar(@{$cfg->{'client_group_map'}}) > 0)) {
        foreach my $x (@{$cfg->{'client_group_map'}}) {
            my ($k, $v) = split(/:/, $x);
            $self->{'client_group_map'}{$k} = $v;
        }
    }
    # get service wrapper info
    my @services = @{$cfg->{'supported_services'}};
    my @wrappers = @{$cfg->{'service_wrappers'}};
    my @urls = @{$cfg->{'supported_urls'}};
    for (my $i=0; $i<@services; $i++) {
        $self->{'service_wrappers'}->{$services[$i]} = { 'script' => $wrappers[$i], 'url' => $urls[$i] };
    }
}

### output of run_app, check_app_state:
#{
#    string job_id;
#    string job_state;
#    int position;
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
    # add this service to read ACL
    $self->_awe_action('job', $job->{id}.'/acl/read', 'put', 'users='.$self->service_auth_name);
    # event log
    $self->_log_event("run_app", "job ".$job->{id}." created for app ".$app->{name});
    # get app info
    my $output = $self->check_app_state(undef, $job);
    # log it
    my $job_dir = $self->log_dir."/log/".$output->{job_id};
    unless (-d $job_dir) {
        mkdir($job_dir);
    }
    open(APPF, ">$job_dir/app.json");
    print APPF $self->json->encode($app);
    close(APPF);
    open(AWFF, ">$job_dir/workflow.json");
    print AWFF $workflow;
    close(AWFF);
    # done
    return $output;
}

sub compose_app {
    my ($self, $app, $user_name) = @_;

    # event log
    $self->_log_event("compose_app", "app ".$app->{name}." submitted by ".$user_name);

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
            print STDERR "[step error] invalid step type '".$step->{type}."' for ".$step->{step_id}."\n";
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
            inputs     => "",
            client_group => exists($self->client_group_map->{$service->{service_name}}) ? $self->client_group_map->{$service->{service_name}} : ""
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
            # we have no wrapper
            unless (exists $self->service_wrappers->{$service->{service_name}}) {
                print STDERR "[service error] unsupported service '".$service->{service_name}."' for ".$step->{step_id}."\n";
                die "[service error] unsupported service '".$service->{service_name}."' for ".$step->{step_id}.":";
            }
            my $fname = 'parameters.json';
            my $arg_hash = $self->_hashify_args($step->{parameters});
            my $input_hash = $self->_post_shock_file($in_attr, $arg_hash, $fname);
            $task_vars->{inputs}   = '"inputs": '.$self->json->encode($input_hash).",\n";
            $task_vars->{cmd_name} = $self->service_wrappers->{$service->{service_name}}{script};
            $task_vars->{arg_list} = join(" ", (
                "--command",
                $service->{method_name},
                "--param_file",
                "@".$fname,
                "--ws_url",
                $self->ws_url
            ));
            # use url passed in app, else use url in config
            if ($service->{service_url}) {
                $task_vars->{arg_list} .= " --service_url ".$service->{service_url};
            } else {
                $task_vars->{arg_list} .= " --service_url ".$self->service_wrappers->{$service->{service_name}}{url};
            }
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
                $task_vars->{arg_list} = join(" ", (
                    "--command",
                    $service->{method_name},
                    "--param_file",
                    "@".$fname,
                    "--ws_url",
                    $self->ws_url
                ));
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
    # event log
    $self->_log_event("check_app_state", "job ".$job->{id}." queried, state = ".$job->{state});
    # set output
    my $output = {
        job_id          => $job->{id},
        job_state       => $job->{state},
        submit_time     => $job->{info}{submittime},
        start_time      => "",
        complete_time   => "",
        position        => 0,
        running_step_id => "",
        step_outputs    => {},
        step_errors     => {}
    };
    # get timestamps
    if ($job->{info}{startedtime} && ($job->{info}{startedtime} ne '0001-01-01T00:00:00Z')) {
        $output->{start_time} = $job->{info}{startedtime};
    }
    if ($job->{info}{completedtime} && ($job->{info}{completedtime} ne '0001-01-01T00:00:00Z')) {
        $output->{complete_time} = $job->{info}{completedtime};
    }
    # get position
    my $result = $self->_awe_action('job', $job_id, 'get', 'position');
    if (ref($result) && (ref($result) eq 'HASH')) {
        if ($result->{position}) {
            $output->{position} = $result->{position};
        }
    }
    # parse each task
    # assume each task has 1 workunit
    foreach my $task (@{$job->{tasks}}) {
        my $step_id = $task->{userattr}->{step};
        my $running = (($task->{state} eq 'queued') || ($task->{state} eq 'in-progress')) ? 1 : 0;
        # get running
        if ($running) {
            $output->{running_step_id} = $step_id;
        }
        # get stdout text
        my $stdout = "";
        if (exists($task->{outputs}{'awe_stdout.txt'}) && $task->{outputs}{'awe_stdout.txt'}{url}) {
            $stdout = $self->_get_shock_file($task->{outputs}{'awe_stdout.txt'}{url});
        } elsif ($running || ($task->{state} eq 'suspend')) {
            $stdout = $self->_awe_action('work', $task->{taskid}.'_0', 'get', 'report=stdout');
        }
        if ($stdout) {
            $output->{step_outputs}{$step_id} = $stdout;
        }
        # get stderr text
        my $stderr = "";
        if (exists($task->{outputs}{'awe_stderr.txt'}) && $task->{outputs}{'awe_stderr.txt'}{url}) {
            $stderr = $self->_get_shock_file($task->{outputs}{'awe_stderr.txt'}{url});
        } elsif ($running || ($task->{state} eq 'suspend')) {
            $stderr = $self->_awe_action('work', $task->{taskid}.'_0', 'get', 'report=stderr');
        }
        if ($stderr) {
            $output->{step_errors}{$step_id} = $stderr;
        }
    }
    # log it if completed
    if (($output->{job_state} eq 'completed') || ($output->{job_state} eq 'suspend')) {
        my $job_dir = $self->log_dir."/log/".$output->{job_id};
        unless (-d $job_dir) {
            mkdir($job_dir);
        }
        open(JOBF, ">$job_dir/job.json");
        print JOBF $self->json->encode($job);
        close(JOBF);
    }
    return $output;
}

sub suspend_app {
    my ($self, $job_id) = @_;
    $self->_log_event("suspend_app", "job ".$job_id." suspended");
    my $result = $self->_awe_action('job', $job_id, 'put', 'suspend');
    return ($result =~ /^job suspended/) ? "success" : "failure";
}

sub resume_app {
    my ($self, $job_id) = @_;
    $self->_log_event("resume_app", "job ".$job_id." resumed");
    my $result = $self->_awe_action('job', $job_id, 'put', 'resume');
    return ($result =~ /^job resumed/) ? "success" : "failure";
}

sub delete_app {
    my ($self, $job_id) = @_;
    $self->_log_event("delete_app", "job ".$job_id." deleted");
    my $result = $self->_awe_action('job', $job_id, 'delete');
    return ($result =~ /^job deleted/) ? "success" : "failure";
}

sub list_config {
    my ($self) = @_;
    $self->_log_event("list_config", "anonymous");
    my $cfg = {
        log_dir   => $self->log_dir,
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

sub _log_event {
    my ($self, $action, $msg) = @_;
    my $events = $self->log_dir."/event.log";
    open(LOGF, ">>$events");
    print LOGF strftime("%Y-%m-%dT%H:%M:%S", localtime)."\t".$action."\t".$msg."\n";
    close(LOGF);
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
            # use service token for GET requests
            @args = ('Authorization', 'OAuth '.$self->service_auth_token);
            $tmp = $self->agent->get($url, @args);
        }
        $response = $self->json->decode( $tmp->content );
    };

    if ($@ || (! ref($response))) {
        if ((! $@) || ($@ =~ /malformed JSON string/)) {
            print STDERR "[awe error] unable to connect to AWE server\n";
            die "[awe error] unable to connect to AWE server:";
        } else {
            print STDERR "[awe error] ".$@."\n";
            die "[awe error] ".$@.":";
        }
    } elsif (exists($response->{error}) && $response->{error}) {        
        my $err = $response->{error}[0];
        # special exception for empty stdout / stderr
        if ($err =~ /log type \S+ not found/) {
            return "";
        }
        # special exception for lost workunit
        if ($err =~ /no workunit found/) {
            return "";
        }
        # special exception for position query
        if ($options && ($options eq 'position')) {
            return {"position" => 0};
        }
        # make message more useful
        if ($err eq "Not Found") {
            $err = "$type $id does not exist";
        }
        print STDERR "[awe error] ".$err."\n";
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
            print STDERR "[awe error] unable to connect to AWE server\n";
            die "[awe error] unable to connect to AWE server:";
        } else {
            print STDERR "[awe error] ".$@."\n";
            die "[awe error] ".$@.":";
        }
    } elsif (exists($response->{error}) && $response->{error}) {
        print STDERR "[awe error] ".$response->{error}[0]."\n";
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
        print STDERR "[shock error] ".($@ || "unable to connect to Shock server")."\n";
        die "[shock error] ".($@ || "unable to connect to Shock server").":";
    }
    
    # check response code, skip 401 and throw error on rest
    if ($response->code == 200) {
        return $response->content;
    } elsif ($response->code == 401) {
        return "";
    } else {
        my $message = "[shock error] ".$response->code." ".$response->message;
        eval {
            my $json = $self->json->decode( $response->content );
            if (exists($json->{error}) && $json->{error}) {
                $message = "[shock error] ".$json->{status}." ".$json->{error}[0];
            }
        };
        print STDERR $message."\n";
        die $message.":";
    }
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
            print STDERR "[shock error] unable to connect to Shock server\n";
            die "[shock error] unable to connect to Shock server:";
        } else {
            print STDERR "[shock error] ".$@."\n";
            die "[shock error] ".$@.":";
        }
    } elsif (exists($response->{error}) && $response->{error}) {
        print STDERR "[shock error] ".$response->{error}[0]."\n";
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

# treat array as json array
# this is for service mode
sub _hashify_args {
    my ($self, $params) = @_;
    my $arg_hash = {};
    for (my $i=0; $i<@$params; $i++) {
        my $p = $params->[$i];
        unless ($p->{label}) {
            print STDERR "[step error] parameter number ".$i." is not valid, label is missing\n";
            die "[step error] parameter number ".$i." is not valid, label is missing:";
        }
        unless ($p->{type}) {
            print STDERR "[step error] parameter number ".$i." is not valid, type is missing\n";
            die "[step error] parameter number ".$i." is not valid, type is missing:";
        }
        eval {
            if ($p->{type} eq 'string') {
                $arg_hash->{$p->{label}} = $p->{value};
            } elsif ($p->{type} eq 'int') {
                $arg_hash->{$p->{label}} = int($p->{value});
            } elsif ($p->{type} eq 'float') {
                $arg_hash->{$p->{label}} = $p->{value} * 1.0;
            } elsif ($p->{type} eq 'array') {
                $arg_hash->{$p->{label}} = $self->json->decode($p->{value});
            }
        };
        if ($@) {
            print STDERR "[step error] parameter number ".$i." is not valid, value is not of type '".$p->{type}."'\n";
            die "[step error] parameter number ".$i." is not valid, value is not of type '".$p->{type}."':";
        }
    }
    return $arg_hash;
}

# treat array as multiple inputs of same label
# this is for script mode with workspace input and/or output
sub _minify_args {
    my ($self, $params) = @_;
    my $arg_min = [];
    for (my $i=0; $i<@$params; $i++) {
        my $p = $params->[$i];
        if ($p->{label} =~ /\s/) {
            print STDERR "[step error] parameter number ".$i." is not valid, label '".$p->{label}."' may not contain whitspace\n";
            die "[step error] parameter number ".$i." is not valid, label '".$p->{label}."' may not contain whitspace:";
        }
        unless ($p->{type}) {
            print STDERR "[step error] parameter number ".$i." is not valid, type is missing\n";
            die "[step error] parameter number ".$i." is not valid, type is missing:";
        }
        if ($p->{type} eq 'array') {
            my $val_array = $self->json->decode($p->{value});
            foreach my $val (@$val_array) {
                if (! $val) {
                    next;
                }
                push @$arg_min, {
                    label           => $p->{label},
                    value           => $val,
                    is_workspace_id => $p->{is_workspace_id},
                    is_input        => $p->{ws_object}{is_input},
                    workspace_name  => $p->{ws_object}{workspace_name},
                    object_type     => $p->{ws_object}{object_type}
                };
            }
        } else {
            push @$arg_min, {
                label           => $p->{label},
                value           => $p->{value},
                is_workspace_id => $p->{is_workspace_id},
                is_input        => $p->{ws_object}{is_input},
                workspace_name  => $p->{ws_object}{workspace_name},
                object_type     => $p->{ws_object}{object_type}
            };
        }
    }
    return $arg_min;
}

# this is for script mode with no workspace input and/or output
sub _stringify_args {
    my ($self, $params) = @_;
    my $arg_min = $self->_minify_args($params); # use this to unroll arrays
    my @arg_list = ();
    foreach my $arg (@$arg_min) {
        # short option
        if (length($arg->{label}) == 1) {
            push @arg_list, "-".$arg->{label};
        }
        # long option
        elsif (length($arg->{label}) > 1) {
            push @arg_list, "--".$arg->{label};
        }
        # has value
        if ($arg->{value}) {
            push @arg_list, $arg->{value};
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
        "dependsOn": [[% depends_on %]],
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
        "clientgroups": "[% client_group %]",
        "taskid": "[% this_task %]",
        "totalwork": 1
    });
}

