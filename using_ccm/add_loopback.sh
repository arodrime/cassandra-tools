#!/bin/bash

nodes=3
datacenters=1
if [ $# -gt 0 ]
then
    re='^[0-9]+$'
    if [[ $1 =~ $re ]]
    then
        nodes=$1
    else
        echo "WARN: First argument is not a number, using $nodes as the number of nodes per DC" >&2
    fi
fi

if [ $# -gt 1 ]
then
    re='^[0-9]+$'
    if [[ $2 =~ $re ]]
    then
        datacenters=$2
    else
        echo "WARN: Second argument is not a number, using $datacenters as the number of DC" >&2
    fi
fi

for dc in $(seq $datacenters)
do
    echo "DC $dc"
    for node in $(seq $nodes)
    do
        cmd="ifconfig lo0 alias 127.0.$((dc-1)).$node up"
        echo $cmd
        sudo $cmd
    done
done
