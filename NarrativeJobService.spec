module NarrativeJobService {

    /* @range [0,1] */
    typedef int boolean;
    
    /*
        service_name - deployable KBase module
        method_name - name of service command or script to invoke
    */
    
    typedef structure {
        string service_name;
        string method_name;
        string service_url;
    } service_method;

    typedef structure {
        string service_name;
        string method_name;
        boolean has_files;
    } script_method;
    
    /*
        label - label of parameter, can be empty string for positional parameters
        value - value of parameter
        step_source - step_id that parameter derives from
        is_workspace_id - parameter is a workspace id (value is object name)
        # the below are only used if is_workspace_id is true
            is_input - parameter is an input (true) or output (false)
            workspace_name - name of workspace
            object_type - name of object type
    */

    typedef structure {
        string workspace_name;
        string object_type;
        boolean is_input;
    } workspace_object;
    
    typedef structure {
        string label;
        string value;
        string step_source;
        boolean is_workspace_id;
        workspace_object ws_object;
    } step_parameter;
    
    /*
        type - 'service' or 'script'
    */
    typedef structure {
        string step_id;
        string type;
        service_method service;
        script_method script;
        list<step_parameter> parameters;
        boolean is_long_running;
    } step;

    typedef structure {
        string name;
        list<step> steps;
    } app;

    /*
        job_id - id of job running app
        job_state - 'queued', 'running', 'completed', or 'error'
        running_step_id - id of step currently running
        step_outputs - mapping step_id to stdout text produced by step, only for completed or errored steps
        step_outputs - mapping step_id to stderr text produced by step, only for completed or errored steps
    */
    typedef structure {
        string job_id;
        string job_state;
        string running_step_id;
        mapping<string, string> step_outputs;
        mapping<string, string> step_errors;
    } app_state;

    funcdef run_app(app app) returns (app_state) authentication required;
    
    funcdef compose_app(app app) returns (string workflow) authentication required;

    funcdef check_app_state(string job_id) returns (app_state) authentication required;

    /*
        status - 'success' or 'failure' of action
    */

    funcdef suspend_app(string job_id) returns (string status) authentication required;

    funcdef resume_app(string job_id) returns (string status) authentication required;

    funcdef delete_app(string job_id) returns (string status) authentication required;
    
    funcdef list_config() returns (mapping<string, string>) authentication optional;
};
