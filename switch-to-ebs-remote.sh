echo "Will abort if any command fails."
set -e 
set -o pipefail

echo "Mounting EBS volumes"
sudo mkdir -p /mounts/var/cassandra/data/data
sudo mkdir -p /mounts/var/cassandra/data/commitlog
sudo mount -o rw /dev/xvdf /mounts/var/cassandra/data/data
sudo mount -o rw /dev/xvdg /mounts/var/cassandra/data/commitlog
df -h
sleep 2

echo "Clearing EBS volumes"
rm -r /mounts/var/cassandra/data/data/*
rm -r /mounts/var/cassandra/data/commitlog/*
sleep 2

echo "Listing data and commitlog directories"
ls -al /mounts/var/cassandra/data/data
ls -al /mounts/var/cassandra/data/commitlog
sleep 2

echo "Listing Docker containers"
docker ps

export CONTAINER_ID=$(docker ps -q)
export LOCAL_IP=$(curl -Ls -m 4 http://169.254.169.254/latest/meta-data/local-ipv4)
export OPSCENTER_IP=10.10.10.10

echo "Stopping container with ID: $CONTAINER_ID in 10 seconds. Will copy files and restart."
sleep 10
docker kill $CONTAINER_ID

echo "Copying data to EBS volumes"
DATA_SUBDIRS="OpsCenter prod_rate_limit_kv prod_reco_kv prod_scds_kv prod_session_kv saved_caches system system_traces tracking_100p"
for DIR in $DATA_SUBDIRS; do
    echo "Copying $DIR."
    cp -r /mounts/var/cassandra/data/$DIR /mounts/var/cassandra/data/data/
    echo "Done."
done
echo "Copied data."

echo "Copying commitlog to EBS volumes"
cp -r /mounts/var/cassandra/data/commit_logs/* /mounts/var/cassandra/data/commitlog/
echo "Copied commitlog."

echo "Running Docker again"
docker run -d --log-driver=syslog --name=taupageapp --restart=on-failure:10 \
    -e APPLICATION_ID=cassandra \
    -e APPLICATION_VERSION=0.1.0 \
    -e SNITCH=GossipingPropertyFileSnitch \
    -e OPSCENTER=$OPSCENTER_IP \
    -e CLUSTER_NAME=My-Cassandra \
    -e DATA_DIR=/var/cassandra/data/data \
    -e COMMIT_LOG_DIR=/var/cassandra/data/commitlog \
    -e TTL=120 \
    -v /mounts/var/cassandra/data/data:/var/cassandra/data/data \
    -v /mounts/var/cassandra/data/commitlog:/var/cassandra/data/commitlog \
    -v /meta:/meta:ro \
    -v /opt/proprietary/newrelic:/data/newrelic:rw \
    -v /opt/proprietary/newrelic:/agents/newrelic:rw \
    -e CREDENTIALS_DIR=/meta/credentials \
    -p 7000:7000 \
    -p 9042:9042 \
    -p 61621:61621 \
    -p 9160:9160 \
    -p 8778:8778 \
    -p 7199:7199 \
    --net=host \
    registry.opensource.zalan.do/mop/stups-cassandra:2.0.17-p0-SNAPSHOT
sleep 15

echo "Configuring OpsCenter agent in a hacky way"
ADDRESS_YAML="stomp_interface: $OPSCENTER_IP\nhosts: [\"$LOCAL_IP\"]\ncassandra_conf: /opt/cassandra/conf/cassandra.yaml"
echo -e $ADDRESS_YAML > address.yaml
echo "address.yaml:"
cat address.yaml
docker cp address.yaml $CONTAINER_ID:/var/lib/datastax-agent/conf/address.yaml
docker exec -it $CONTAINER_ID service datastax-agent restart
sleep 10

echo "Running nodetool repair in 10 seconds."
sleep 10

echo "Running nodetool repair -h $LOCAL_IP"
docker exec -it $CONTAINER_ID /opt/cassandra/bin/nodetool repair -h $LOCAL_IP

