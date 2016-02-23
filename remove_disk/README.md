# Removing a disk from a Cassandra node

## Prepare the nodes

I am supposing you want to remove **one** disk by transferring its data to **one** other disk.
All the following operations can be run in parallel, except the last step, running the script as it restarts the node.

1. Make sure node is eligible for the removal (enough disk space left on the remaining disk)

        grep "data_fi" /etc/cassandra/conf/cassandra.yaml -A3
        df -h | grep cassandra

2. Change config and remove the disk you want to go away.

        sudo vim /etc/cassandra/conf/cassandra.yaml

3. 1st rsync - The idea is to have the node down for the shortest time possible, even if this makes the operation slower.

        screen -S rsync
        sudo rsync -azvP --delete-before <path_old_disk>/data/ <path_new_disk>/data-tmp/

4. When first sync finishes, disable compaction and stop compaction to avoid files to be compacted and transferring again the same files. I do not recommend this before the first rsync as we don't want the cluster to stop compacting for too long. If your dataset is small, it should be fine doing this before first rsync and only do 2 rsync.

        nodetool disableautocompaction
        nodetool stop compaction
        nodetool compactionstats

5. Drop the script on the node, make it executable and configure variables (https://github.com/arodrime/cassandra-tools/blob/master/remove_disk/remove_extra_disk.sh#L2-L4)

        curl -Os https://github.com/arodrime/cassandra-tools/blob/master/remove_disk/remove_extra_disk.sh
        chmod u+x remove_extra_disk.sh
        vim remove_extra_disk.sh # Set 'User defined variables'

6. 2nd rsync

        screen -r rsync
        sudo rsync -azvP --delete-before <path_old_disk>/data/ <path_new_disk>/data-tmp/

7. 3rd rsync (if needed, see the diff)

        sudo du -sh <path_old_disk> && sudo du -sh <path_new_disk>/data-tmp
        sudo rsync -azvP --delete-before <path_old_disk>/data/ <path_new_disk>/data-tmp/

8. Check conf

        grep "data_fi" /etc/cassandra/conf/cassandra.yaml -A3

## Run the script `remove_extra_disk.sh`

* The script stops the node, so should be run *sequentially*.
* It performs 2 more rsync:
    * The first one to take the diff between the end of 3rd `rsync` and the moment you stop the node, it should be a few seconds, maybe minutes, depending how fast the script was run after 3rd `rsync` ended and on the throughput.
    * The second `rsync` in the script is a 'control' one. I just like to control things. Running it, we expect to see that there is no diff. It is just a way to stop the script if for some reason data is still being appended to `old-dir` (Cassandra not stopped correctly or some other weird behavior). I guess this could be replaced/completed with a check on Cassandra service making sure it is down.
* Next step in the script is to move all the files from `tmp-dir` to `new-dir` (the proper data folder remaining after the operation). This is an instant operation as files are not really moved as they already are on the disk as mentioned earlier.
* Finally the script unmount the disk and remove the `old-dir`.

**Run the script** - Node by node ! - and monitor

        ./remove_extra_disk.sh
        sudo tail -100f /var/log/cassandra/system.log
        ...
