#!/usr/bin/env python

import json
import os
import subprocess
import sys
from optparse import OptionParser

VERSION = '1'
AUTH_LIST = "Jared Bischof, Travis Harrison, Folker Meyer, Tobias Paczian, Andreas Wilke"

prehelp = """
NAME
    njs-run-step

VERSION
    %s

SYNOPSIS
    njs-run-step [--help, --token=<KBase auth token>, --params=<params.json>] [command]

DESCRIPTION
    Takes as input the name of a command that will be executed.
    
    Options include 1) --params, a JSON document input that defines the parameters that should be added when executing the command and 2) --token, a KBase auth token variable to be placed in the environment for command execution.  By default, if the KB_AUTH_TOKEN environment variable is aleady in the users environment then this doesn't need to be set.

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

def validate_and_get_cmd_args(params_array):
    params = []
    for k, v in enumerate(params_array):
        if "label" in v:
            params.append(v["label"])
        else:
            sys.stderr.write("ERROR, parameter number " + k + " is not valid because it has no label")
            return False, []
        if "value" in v:
            params.append(v["value"])
    return True, params

def check_for_ws_cmds(params_array):
    need_upload = False
    need_download = False
    for i in params_array:
        if (("is_workspace_id" in i) and (i["is_workspace_id"] == True)):
            if (("is_input" in i) and (i["is_input"] == True)):
                need_download = True
            else:
                need_upload = True

    if (need_upload == True):
        if (not is_cmd("ws-load")):
            sys.stderr.write("ERROR, ws-load command was not found and is necessary for uploading outputs to the workspace.\n")
            return False

    if (need_download == True):
        if (not is_cmd("ws-get")):
            sys.stderr.write("ERROR, ws-get command was not found and is necessary for downloading inputs from the workspace.\n")
            return False

    if (not 'KB_AUTH_TOKEN' in os.environ):
        sys.stderr.write("ERROR, 'KB_AUTH_TOKEN' must be set in your environment or via the --token option if you're uploading or downloading from the workspace.\n")
        return False

    return True

def download_ws_objects(params_array):
    for k,v in enumerate(params_array):
        if (("is_workspace_id" in v) and (v["is_workspace_id"] == True) and ("is_input" in v) and (v["is_input"] == True)):
            if (subprocess.call(['ws-get', v["label"]], stdout=subprocess.PIPE, stderr=subprocess.PIPE) != 0):
                sys.stderr.write("ERROR, cound load download input from workspace for parameter number: '" + k + "', labeled: '" + v["label"] + "'.\n")
                return 1

def upload_ws_objects(params_array):
    for k,v in enumerate(params_array):
        if (("is_workspace_id" in v) and (v["is_workspace_id"] == True)):
            if (subprocess.call(['ws-load', v["label"]], stdout=subprocess.PIPE, stderr=subprocess.PIPE) != 0):
                sys.stderr.write("ERROR, cound load download input from workspace for parameter number: '" + k + "', labeled: '" + v["label"] + "'.\n")
                return 1

def is_cmd(cmd):
    return subprocess.call("type " + cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE) == 0

def main(args):
    OptionParser.format_description = lambda self, formatter: self.description
    OptionParser.format_epilog = lambda self, formatter: self.epilog
    parser = OptionParser(usage='', description=prehelp%VERSION, epilog=posthelp%AUTH_LIST)
    parser.add_option("", "--params", dest="params", default=None, help="JSON parameters document")
    parser.add_option("", "--token", dest="token", default=None, help="KBase auth token")

    # get inputs
    (opts, args) = parser.parse_args()
    if (len(args) < 1):
        sys.stderr.write("ERROR, the command to be executed is required.\n")
        return 1

    cmd = args[0]
    if (not is_cmd(cmd)):
        sys.stderr.write("ERROR, command: '" + cmd + "' not found.\n")
	return 1

    if opts.token:
        os.environ['KB_AUTH_TOKEN'] = opts.token

    cmd_args = [cmd]
    if (opts.params != None and opts.params != ''):
        params_fh = open(opts.params, 'r')
        params_array = json.load(params_fh)
        valid, add_cmd_args = get_cmd_args(params_array)
        if (valid == True):
            cmd_args.extend(add_cmd_args)
        else:
            return 1
        if (len(params_array) > 0):
            if (check_for_ws_cmds(params_array) == False):
                return 1
            if (download_ws_objects(params_array) == False):
                return 1

    p = subprocess.Popen(cmd_args, stdout=sys.stdout, stderr=sys.stderr)

    if (opts.params != None and opts.params != '' and len(params_array) > 0):
        if (upload_ws_objects(params_array) == False):
            return 1

if __name__ == "__main__":
    sys.exit( main(sys.argv) )
