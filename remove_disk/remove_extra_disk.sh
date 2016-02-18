#!/bin/bash
# User defined variables
path_old_disk=/var/lib/cassandra
path_new_disk=/var/lib/cassandra_new

# Once we have are ready, see README, we need to stop cassandra
success=0
nodetool drain && sleep 10 && sudo service cassandra stop && sleep 10 && success=1

# Sync again to get the diff
if ((success)); then
  success=0
  sudo rsync -azvP --delete-before $path_old_disk/data/ $path_new_disk/data-tmp/ && success=1
else
  exit 1
fi

# Repeat to have the rsync confirming dir A = dir B. Sleep 5 to let you time to interrupt if something is wrong.
if ((success)); then
  success=0
  sudo rsync -azvP --delete-before $path_old_disk/data/ $path_new_disk/data-tmp/ && success=1
  sleep 5
else
  exit 1
fi

# Move files to the "data" directory of cassandra from data-tmp. This is a very fast op, no matter the data size
if ((success)); then
  for dir in $(sudo find $path_new_disk/data-tmp -type d)
  do
    dest=$(echo $dir | sed 's/data-tmp/data/g')
    echo "Creating directory $dest (if not exist)..."
    sudo mkdir -p $dest
    sudo chown cassandra: $dest
    echo "Moving files (depth 1) from $dir to $dest..."
    sudo find $dir -maxdepth 1 -name "*" -type f -exec mv {} $dest \;
    sudo chown -R cassandra: $dest
  done
else
  exit 1
fi

# Unmount old disk from the system
# Remove the folder to make sure Cassandra won't find it if misconfigured
if ((! $(sudo find $path_new_disk/data-tmp -name "*.db" | wc -l))); then
  success=0
  sudo umount -d $path_old_disk && sudo rm -rf $path_old_disk $path_new_disk/data-tmp && success=1
else
  exit 1
fi

# Finally restart Cassandra
if ((success)); then
  sudo service cassandra start
fi
