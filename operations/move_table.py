__author__ = 'Alain Rodriguez'
__email__ = 'arodrime@gmail.com'

import argparse
import re
import os
import sys

# Constants
VERSION = "1.0"


def handle_options():
    parser = argparse.ArgumentParser()
    parser.add_argument("--datacenters", help="DC1:RF1,DC2:RF2 for the new_keyspace")
    parser.add_argument("--old-keyspace", help="The name of the keyspace to use as source")
    parser.add_argument("--old-table", help="The name of the table to use as source")
    parser.add_argument("--new-keyspace", help="The name of the new keyspace to use (leave blank to just rename a table with no keyspace switch)")
    parser.add_argument("--new-table", help="The name of the new table to use (leave blank to switch keyspace without renaming the table)")
    parser.add_argument("-l", "--hard-link", help="Chose to hard links SSTables instead of copying them (default)", action="store_true")
    parser.add_argument('--version', action='version', version='%(prog)s '+VERSION)
    parser.add_argument("-n", "--dry-run", help="add the flag to dry run", action="store_true")
    parser.add_argument("-v", "--verbose", help="increase output verbosity", action="store_true")
    args = parser.parse_args()

    print args

    # Check that we heve enough info to either rename a table, Split a Keyspace or both things at once
    if not args.old_keyspace or not args.old_table:
        parser.error("You must specify the origin Keyspace and Table")
    if not (args.new_keyspace or args.new_table):
        parser.error("You must specify either a destination Keyspace, a destination Table or both")
    if not args.datacenters and args.new_keyspace:
        parser.error("As destination Keyspace, you need to add '--datacenter DC1:RF1[,DC2:RF2]'"
                     " to set Replication Factor for the new Keyspace")
    pattern = re.compile("^((.*:\d+)(,.*:\d+)*)$")
    if args.datacenters and pattern.match(args.datacenters):
        # We have to split this arg to separate each DC and name / RF for each DC.
        datacenters = {}
        for i, item in enumerate(args.datacenters.split(",")):
            datacenters[i] = item.split(":")
            args.datacenters = datacenters
    else:
        parser.error("--datacenter option form is DC1:RF1[,DC2:RF2] - Regexp to match is ^((.*:\d+)(,.*:\d+)*)$")
    # if any of the new_* args are empty, set the old value. This property is used further
    if not args.new_keyspace:
        args.new_keyspace = args.old_keyspace
    if not args.new_table:
        args.new_table = args.old_table

    return args


def system_call(args, command, info=""):
    if info:
        print(info)
    if args.verbose or args.dry_run:
        print(command)
    if not args.dry_run:
        success = os.system(command)
        if success != 0:
            sys.exit('Following system call did not work properly: ' + command)


def create_keyspace(args):
    # First create keyspace if relevant
    create_keyspace_cmd = 'echo "CREATE KEYSPACE IF NOT EXISTS ' \
                          + args.new_keyspace \
                          + " WITH replication = {'class': 'NetworkTopologyStrategy', "

    dc_number = len(args.datacenters)

    for i in range(0, dc_number):
        create_keyspace_cmd += "'" + args.datacenters.get(i)[0] + "': " + args.datacenters.get(i)[1]
        if i < dc_number-1:
            create_keyspace_cmd += ", "

    create_keyspace_cmd += '};" | cqlsh $(cat /etc/hostname)'
    # On AWS this should work $(curl http://169.254.169.254/latest/meta-data/local-ipv4)
    # Run it.
    system_call(args, create_keyspace_cmd, "Creating new keyspace " + args.new_keyspace)


def create_table(args):
    temp_file = 'temp.cql'
    # Get table description, save it in a file
    table_to_file_cmd = 'echo "DESCRIBE TABLE ' + args.old_table + ';" ' \
                                                                   '| cqlsh $(cat /etc/hostname) -k ' + args.old_keyspace \
                        + ' > ' + temp_file
    system_call(args, table_to_file_cmd, "Dumping " + args.old_keyspace + '.' + args.old_table + " schema")

    # Change keyspace / table name if needed
    if args.new_keyspace != args.old_keyspace:
        set_new_keyspace_cmd = 'sed -i -e s/'+ args.old_keyspace + '/' + args.new_keyspace + '/g temp.cql'
        system_call(args, set_new_keyspace_cmd, "Changing keyspace name in the dump")
    if args.new_table != args.old_table:
        set_new_table_cmd = 'sed -i -e s/'+ args.old_table + '/' + args.new_table + '/g temp.cql'
        system_call(args, set_new_table_cmd, "Changing table name in the dump")

    set_check_cmd = 'sed -i -e "s/CREATE TABLE/CREATE TABLE IF NOT EXISTS/g" temp.cql'
    system_call(args, set_check_cmd, "Adding IF NOT EXISTS check on table creation")

    # Create new table
    create_new_table = 'cqlsh -f temp.cql -k ' + args.new_keyspace + ' $(cat /etc/hostname)'
    system_call(args, create_new_table, "Creating new table " + args.new_keyspace + '.' + args.new_table)

def create_snapshot(args):
    # Create new table
    create_new_table = 'nodetool snapshot ' + args.old_keyspace + ' -cf ' + args.old_table + ' -t split_keyspace_$(date +%Y%m%d%H%M)'
    system_call(args, create_new_table, "Creating snapshot")


def populate_new_table(args):
    if args.hard_link:
        # Through Hard Links
        populate_cmd = 'ln /raid0/cassandra/data/' \
                       + args.old_keyspace \
                       + '/' \
                       + args.old_table \
                       + '/snapshots/split_keyspace/* ' \
                       + '/raid0/cassandra/data/' \
                       + args.new_keyspace \
                       + '/' \
                       + args.new_table \
                       + '/'
    else:
        # Through Copy
        populate_cmd = 'cp /raid0/cassandra/data/' \
                       + args.old_keyspace \
                       + '/' \
                       + args.old_table \
                       + '/snapshots/split_keyspace/* ' \
                       + '/raid0/cassandra/data/' \
                       + args.new_keyspace \
                       + '/' \
                       + args.new_table \
                       + '/'
    system_call(args, populate_cmd, "Getting new SStables for " + args.new_keyspace + '.' + args.new_table)

    rename_files_cmd = "rename 's/" \
                       + args.old_keyspace \
                       + "/" \
                       + args.new_keyspace \
                       + "/g' /raid0/cassandra/data/" \
                       + args.new_keyspace \
                       + "/" \
                       + args.new_table \
                       + "/* && rename 's/" \
                       + args.old_table \
                       + "/" \
                       + args.new_table \
                       + "/g' /raid0/cassandra/data/" \
                       + args.new_keyspace \
                       + "/" \
                       + args.new_table \
                       + "/*"

    system_call(args, rename_files_cmd, "Renaming new SStables to use new Keyspace and Table names")


def refresh_data(args):
    create_new_table = 'nodetool refresh ' + args.new_keyspace + ' ' + args.new_table
    system_call(args, create_new_table, "Loading new SSTables for " + args.new_keyspace + '.' + args.new_table)


def show_to_do(args):
    print("");
    print("You now should: ")
    print("  - Switch reads to " + args.new_keyspace + '.' + args.new_table)
    print("  - Remove forked writes / Start back writing, but only to " + args.new_keyspace + '.' + args.new_table)
    print("  - Remove old table by running the following CQL query on ANY node: DROP TABLE " + args.old_keyspace + '.' + args.old_table + ";")
    print("  - Clean snapshots by running the following command on EACH node: nodetool clearsnapshot -t split_keyspace " + args.new_keyspace)


def main():
    args = handle_options()
    if args.datacenters and args.new_keyspace:
        create_keyspace(args)
    if args.new_table:
        create_table(args)
    create_snapshot(args)
    populate_new_table(args)
    refresh_data(args)
    show_to_do(args)


if __name__ == "__main__":
    main()
