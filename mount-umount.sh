sudo mkdir -p /mounts/var/cassandra/data/data
sudo mkdir -p /mounts/var/cassandra/data/commitlog

sudo mount -o rw /dev/xvdf /mounts/var/cassandra/data/data
sudo mount -o rw /dev/xvdg /mounts/var/cassandra/data/commitlog

sudo umount /dev/xvdf
sudo umount /dev/xvdg
