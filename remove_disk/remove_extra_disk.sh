#!/bin/bash
#
# The MIT License (MIT)
# Copyright (c) 2016 The Last Pickle
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
# The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
#
#
#
# Script description
#
# - The script stops the node, so should be run sequentially.
# - It performs 2 more rsync:
#   - The first one to take the diff between the end of 3rd rsync and the moment you stop the node, it should be a few seconds, maybe minutes, depending how fast the script was run after 3rd rsync ended and on the throughput.
#   - The second rsync in the script is a 'control' one. I just like to control things. Running it, we expect to see that there is no diff. It is just a way to stop the script if for some reason data is still being appended to old-dir (Cassandra not stopped correctly or some other weird behavior). I guess this could be replaced/completed with a check on Cassandra service making sure it is down.
# - Next step in the script is to move all the files from tmp-dir to new-dir (the proper data folder remaining after the operation). This is an instant operation as files are not really moved as they already are on the disk as mentioned earlier.
# - Finally the script unmount the disk and remove the old-dir.
#
#
#
# Author: Alain Rodriguez, for The Last Pickle
# Email: alain@thelastpickle.com

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
