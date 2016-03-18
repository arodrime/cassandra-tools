# Sending a command to a list of servers

Get the script file and make it executable:

    curl -Os https://raw.githubusercontent.com/arodrime/cassandra-tools/master/rolling-ssh/rolling-cmd.sh
	chmod u+x rolling-cmd.sh

Edit the script and change the configuration in the 'User defined variables' block

	#### User defined variables

Use the script to send a command

	./rolling-cmd.sh

or

	./rolling-cmd.sh nodetool compactionstats

Note that the command can be given as the only argument or by setting a variable. It is also possible to drop a script on all the machines and then run them sequentially. I used this technique to have nodes upgraded or java updated on all the nodes for example.

# Examples

## Rolling restart

A safe rolling restart can be performed with something like:

	./rolling-cmd.sh 'ip=$(cat /etc/hostname); nodetool disablethrift && nodetool disablebinary && sleep 5 && nodetool disablegossip && nodetool drain && sleep 10 && sudo service cassandra restart && until echo "SELECT * FROM system.peers LIMIT 1;" | cqlsh $ip > /dev/null 2>&1; do echo "Node $ip is still DOWN"; sleep 10; done && echo "Node $ip is now UP"'
