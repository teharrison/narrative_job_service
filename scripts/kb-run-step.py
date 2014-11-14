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
    kb-run-step

VERSION
    %s

SYNOPSIS
    kb-run-step [--help, --token=<KBase auth token>, --params=<params.json>] [command]

DESCRIPTION
    Takes as input the name of a command that will be executed.
    
    Options include 1) --params, a JSON document input that defines the parameters that should be added when executing the command and 2) --token, a KBase auth token variable to be placed in the environment for command execution.  By default, if the KB_AUTH_TOKEN environment variable is aleady in the users environment then this doesn't need to be set.

    kb-run-step will download input files from, and upload output files to the workspace using the KBase auth token.
"""

posthelp = """
Output
    1. stderr returns stderr from this script and from executed command
    2. stdout returns stdout from this script and from executed command

EXAMPLES
    kb-run-step ls

SEE ALSO
    -

AUTHORS
    %s
"""

def get_cmd_args(params_file):
    params = []
    params_fh = open(params_file, 'r')
    param_array = json.load(params_fh)
    for i in param_array:
        if "name" in i:
            params.append(i["name"])
        if "value" in i:
            params.append(i["value"])
    return params

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
    if (subprocess.call("type " + cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE) != 0):
        sys.stderr.write("ERROR, command not found.\n")
	return 1

    if opts.token:
        os.environ['KB_AUTH_TOKEN'] = opts.token

    cmd_args = [cmd]
    if (opts.params != None and opts.params != ''):
        print opts.params
        cmd_args.extend(get_cmd_args(opts.params))

    p = subprocess.Popen(cmd_args, stdout=sys.stdout, stderr=sys.stderr)

if __name__ == "__main__":
    sys.exit( main(sys.argv) )
