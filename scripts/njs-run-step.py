#!/usr/bin/env python

import json
import os
import subprocess
import sys
import glob
from optparse import OptionParser

VERSION = '1'
AUTH_LIST = "Jared Bischof, Travis Harrison, Folker Meyer, Tobias Paczian, Andreas Wilke"
WS_NAME = ""
OUT_DIR = "workspace_output"

prehelp = """
NAME
    njs-run-step

VERSION
    %s

SYNOPSIS
    njs-run-step [--help, --token=<KBase auth token>, --params=<params.json>] [command]

DESCRIPTION
    Takes as input the name of a command that will be executed.
    
    Options include
        1) --params, a JSON document input that defines the parameters that should be added when executing the command
            format:
            [{
                "label": <string>,
                "value": <string>,
                "is_workspace_id": <boolean>,
                "is_input": <boolean>,
                "workspace_name": <string>,
                "object_type": <string>
            }]
        
        2) --token, a KBase auth token variable to be placed in the environment for command execution.  By default, if the KB_AUTH_TOKEN environment variable is aleady in the users environment then this doesn't need to be set.

    njs-run-step will download input files from, and upload output files to the workspace using the KBase auth token.
"""

posthelp = """
Output
    1. stderr returns stderr from this script and from executed command
    2. stdout returns stdout from this script and from executed command

EXAMPLES
    njs-run-step ls

SEE ALSO
    -

AUTHORS
    %s
"""

#[{
#    label,
#    value,
#    is_workspace_id,
#    is_input,
#    workspace_name,
#    object_type
#}]

def get_cmd_args(params_array):
    global WS_NAME
    params = []
    for i, p in enumerate(params_array):
        # validate general
        if ("label" not in p) or ("value" not in p):
            sys.stderr.write("[error] parameter number %d is not valid because it has no label or value.\n"%(i))
            return False, []
        if len(p["label"].split()) > 1:
            sys.stderr.write("[error] parameter number %d is not valid, label '%s' may not contain whitspace.\n"%(i, p["label"]))
            return False, []
        # validate ws
        if ("is_workspace_id" in p) and p["is_workspace_id"]:
            if not (("is_input" in p) and ("workspace_name" in p) and ("object_type" in p)):
                sys.stderr.write("[error] parameter number %d is not valid because it is missing workspace information.\n"%(i))
                return False, []
            else:
                WS_NAME = p["workspace_name"]
        # short option
        if len(p["label"]) == 1:
            params.append("-"+p["label"])
        # long option
        elif len(p["label"]) > 1:
            params.append("--"+p["label"])
        # has value
        if len(p["value"]) > 0:
            params.append(p["value"])
    return True, params

def check_for_ws_cmds(params_array):
    need_upload = False
    need_download = False
    for p in params_array:
        if ("is_workspace_id" in p) and p["is_workspace_id"]:
            if ("is_input" in p) and p["is_input"]:
                need_download = True
            else:
                need_upload = True
    if need_upload and (not is_cmd("ws-load")):
        sys.stderr.write("[error] ws-load command was not found and is necessary for uploading outputs to the workspace.\n")
        return False
    if need_download and (not is_cmd("ws-get")):
        sys.stderr.write("[error] ws-get command was not found and is necessary for downloading inputs from the workspace.\n")
        return False
    if (need_upload or need_download) and (not is_cmd("ws-workspace")):
        sys.stderr.write("[error] ws-workspace command was not found and is necessary for transfer from the workspace.\n")
        return False
    if (need_upload or need_download) and ('KB_AUTH_TOKEN' not in os.environ):
        sys.stderr.write("[error] 'KB_AUTH_TOKEN' must be set in your environment or via the --token option.\n")
        return False
    return True

def download_ws_objects(params_array):
    for p in params_array:
        if ("is_workspace_id" in p) and p["is_workspace_id"] and p["is_input"]:
            set_ws(p["workspace_name"])
            ws_cmd = ['ws-get', p["value"]]
            ws_file = open(p["value"], 'w')
            if subprocess.call(ws_cmd, stdout=ws_file, stderr=sys.stderr) != 0:
                sys.stderr.write("[error] can not download from workspace: %s/%s.\n"%(p["workspace_name"], p["value"]))
                return False
            ws_file.close()
    return True

def upload_ws_objects(params_array):
    for p in params_array:
        if ("is_workspace_id" in p) and p["is_workspace_id"] and (not p["is_input"]):
            if not upload_ws_obj(p["workspace_name"], p["object_type"], p["value"], p["value"]):
                return False
    return True

def upload_ws_obj(ws_name, obj_type, obj_id, obj_file):
    set_ws(ws_name)
    ws_cmd = ['ws-load', obj_type, obj_id, obj_file]
    if subprocess.call(ws_cmd, stdout=sys.stdout, stderr=sys.stderr) != 0:
        sys.stderr.write("[error] can not upload to workspace: %s/%s.\n"%(ws_name, obj_id))
        return False
    return False

def set_ws(ws_name):
    ws_cmd = ['ws-workspace', ws_name]
    if subprocess.call(ws_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE) != 0:
        sys.stderr.write("[error] can not set workspace %s.\n"%(ws_name))
        return False
    return True

def is_cmd(cmd):
    return subprocess.call("type " + cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE) == 0

def main(args):
    OptionParser.format_description = lambda self, formatter: self.description
    OptionParser.format_epilog = lambda self, formatter: self.epilog
    parser = OptionParser(usage='', description=prehelp%VERSION, epilog=posthelp%AUTH_LIST)
    parser.add_option("-p", "--params", dest="params", default=None, help="JSON parameters document")
    parser.add_option("-t", "--token", dest="token", default=None, help="KBase auth token")

    # get inputs
    (opts, args) = parser.parse_args()
    if len(args) < 1:
        sys.stderr.write("[error] the command to be executed is required.\n")
        return 1
    
    # validate inputs
    cmd = args[0]
    if len(cmd.split()) > 1:
        sys.stderr.write("[error] command: '"+cmd+"' may not contain whitespace.\n")
        return 1
    if not is_cmd(cmd):
        sys.stderr.write("[error] command: '"+cmd+"' not found.\n")
        return 1
    if opts.token:
        os.environ['KB_AUTH_TOKEN'] = opts.token
    cmd_args = [cmd]

    # get params: build args and check ws scripts
    params_array = []
    if opts.params and os.path.isfile(opts.params):
        try:
            params_array = json.load(open(opts.params, 'rU'))
        except ValueError:
            sys.stderr.write("[error] params file '"+opts.params+"' contains invalid JSON.\n")
            return 1
        valid, add_cmd_args = get_cmd_args(params_array)
        if not valid:
            return 1
        cmd_args.extend(add_cmd_args)
        if not check_for_ws_cmds(params_array):
            return 1

    # download
    if not download_ws_objects(params_array):
        return 1
    # run cmd
    p = subprocess.call(cmd_args, stdout=sys.stdout, stderr=sys.stderr)
    if p != 0:
        sys.stderr.write("[error] command: '%s' returned exit status %d.\n"%(cmd, p))
        return p
    # upload
    if not upload_ws_objects(params_array):
        return 1
    # optional upload
    if os.path.isdir(OUT_DIR) and WS_NAME:
        objects = map(lambda x: os.path.splitext(os.path.basename(x))[0], glob.glob(os.path.join(opts.outdir, '*.obj')))
        types = map(lambda x: os.path.splitext(os.path.basename(x))[0], glob.glob(os.path.join(opts.outdir, '*.type')))
        for obj in objects:
            if obj in types:
                obj_type = open(os.path.join(opts.outdir, obj+'.type'), 'r').read().strip()
                if not upload_ws_obj(WS_NAME, obj_type, obj, os.path.join(opts.outdir, obj+'.obj')):
                    return 1
    # done
    return 0

if __name__ == "__main__":
    sys.exit( main(sys.argv) )

