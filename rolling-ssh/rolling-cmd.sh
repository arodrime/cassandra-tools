#!/bin/bash
#
#
# The MIT License (MIT)
# Copyright (c) 2016 The Last Pickle
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
# The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
#
#
# Script description
#
# Run a command defined as a variable or given as an argument to a list of servers
#
#
# Author: Alain Rodriguez, for The Last Pickle
# Email: alain@thelastpickle.com


#### User defined variables

# User to connect a remote node through ssh
user=alain

# timeout for each ssh command
timeout=5

# Select the nodes
# Can be from a file or only aiming at one rack for example:
# $(cat server-list.txt | grep '10.10.50')
some_cassandra_node=localhost # Used to grep all the other nodes IPs
node_list=$(nodetool -h $some_cassandra_node status | awk '{split($0,a," "); print a[2]}'| grep -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')

# The command to run on the previouslyy selected nodes
# Can be passed as the only argument
if [ $# -eq 0 ]
then
    ssh_command='df -h' # Can be either a monitoring or an active command like "nodetool setstreamthroughput 100"
else
    ssh_command="$@"
fi

#### End of "User defined variables" block


# Run the command on selected nodes
for i in $node_list
do
    echo "---- Result for $user@$i ----"
    ssh -A -o ConnectTimeout=$timeout -o StrictHostKeyChecking=no -t $user@$i "$ssh_command" 2> /dev/null || echo 'ko'
done
