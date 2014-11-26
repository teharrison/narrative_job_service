#!/usr/bin/env python

import json
import os
import subprocess
import sys
import random
import requests
from optparse import OptionParser

VERSION = '1'
AUTH_LIST = "Jared Bischof, Travis Harrison, Folker Meyer, Tobias Paczian, Andreas Wilke"

prehelp = """
NAME
    njs-run-rpc

VERSION
    %s

SYNOPSIS
    njs-run-rpc [--help --token=<KBase auth token> --params=<params.json>] --url=<service url> --service=<service name> --method=<method name>

DESCRIPTION
    Runs a JSPN RPC KBase method call based on given options and parameters.
"""

posthelp = """
Output
    1. stderr returns RPC 'error' field
    2. stdout returns RPC 'result' field

EXAMPLES
    njs-run-rpc -h

SEE ALSO
    -

AUTHORS
    %s
"""

def main(args):
    OptionParser.format_description = lambda self, formatter: self.description
    OptionParser.format_epilog = lambda self, formatter: self.epilog
    parser = OptionParser(usage='', description=prehelp%VERSION, epilog=posthelp%AUTH_LIST)
    parser.add_option("-t", "--token", dest="token", default=None, help="KBase auth token")
    parser.add_option("-p", "--params", dest="params", default=None, help="JSON parameters document")
    parser.add_option("-u", "--url", dest="url", default=None, help="JSON RPC KBase service url")
    parser.add_option("-s", "--service", dest="service", default=None, help="JSON RPC KBase service name")
    parser.add_option("-m", "--method", dest="method", default=None, help="JSON RPC KBase service method name")
    
    # get inputs
    (opts, args) = parser.parse_args()
    
    # validate inputs
    if not opts.url:
        sys.stderr.write("[error] missing requred service url\n")
        return 1
    if not opts.service:
        sys.stderr.write("[error] missing requred service name\n")
        return 1
    if not opts.method:
        sys.stderr.write("[error] missing requred service method name\n")
        return 1
    # get from env if missing
    if not opts.token:
        opts.token = os.environ['KB_AUTH_TOKEN']
    
    # get params
    params = []
    if opts.params and os.path.isfile(opts.params):
        try:
            params_array = json.load(open(opts.params, 'rU'))
        except ValueError:
            sys.stderr.write("[error] params file '"+opts.params+"' contains invalid JSON.\n")
            return 1
    
    # build POST
    auth = {"Authorization": opts.token} if opts.token else {}
    body = {
        "method" : opts.service+"."+opts.method,
        "params" : params,
        "id" : random.randint(10000,99999)
    }
    # try POST
    try:
        req = requests.post(opts.url, headers=auth, data=json.dumps(body))
        rj  = req.json()
    except:
        sys.stderr.write("[error] unable to connect to %s service at %s\n"%(opts.service, opts.url))
        return 1
    # got error
    if rj['error']:
        try:
            err = rj['error']['message']
        except:
            err = rj['error']
        sys.stderr.write("[error] %s\n"%(out))
        return 1
    # got result
    try:
        out = json.dumps(rj['result'])
    except:
        out = rj['result']
    sys.stdout.write(out+"\n")
    
    return 0

if __name__ == "__main__":
    sys.exit( main(sys.argv) )
