module NarrativeJobService {

    /* @range [0,1] */
    typedef int boolean;
    
    /*
        service_name - deployable KBase module
    */
    
    typedef structure {
        string service_name;
        string method_name;
    } service_method;

    typedef structure {
        string service_name;
        string script_name;
    } script_method;
    
    /*
        label - label of parameter, can be empty string for positional parameters
        value - value of parameter
        is_input - parameter is an input (true) or output (false), for workspace_id
        step_source - step_id that input derives from
        is_workspace_id - parameter is a workspace id
        is_object - parameter is text encoded JSON
    */
    
    typedef structure {
        string label;
        string value;
        boolean is_input;
        string step_source;
        boolean is_workspace_id;
        boolean is_object;
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

    funcdef run_app(app app, string user_name) returns (app_state) authentication required;

    funcdef check_app_state(string job_id) returns (app_state) authentication required;
    
    funcdef suspend_app(string job_id) returns (app_state) authentication required;
    
    funcdef delete_app(string job_id) returns (app_state) authentication required;
    
    funcdef version() returns (string);
};
