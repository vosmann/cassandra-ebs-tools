# 1. Describe instance that will be replaced (AZ, data and commitlog volume, security group)
# 2. Create instance profile with that role (Only first time; in separate script)
# 3. Kill instance
# 4. Run new instance (tag it, attach volumes, mount them, run docker, restart agent)


echo "Gathering parameters."

IP=$1 # IP address of the node that needs to be replaced.
MINT_BUCKET=
SCALYR_KEY=
TAUPAGE_AMI_ID=
CLUSTER_NAME=
OPSCENTER=
IMAGE=
SEEDS=

APP_ID=reco-cassandra
APP_VERSION=transfer-no-asg
TAG=$APP_ID-$APP_VERSION
INSTANCE_TYPE=c4.2xlarge
INSTANCE_PROFILE_NAME=cassandra-profile

aws ec2 describe-instances --filters Name=private-ip-address,Values=$IP > describe-instance-$IP

INSTANCE_COUNT=$(cat describe-instance-$IP | jq -r '.Reservations[0].Instances | length')
AZ=$(cat describe-instance-$IP | jq -r '.Reservations[0].Instances[0].Placement.AvailabilityZone')
OLD_INSTANCE_ID=$(cat describe-instance-$IP | jq -r '.Reservations[0].Instances[0].InstanceId')
OLD_INSTANCE_IP=$(cat describe-instance-$IP | jq -r '.Reservations[0].Instances[0].PrivateIpAddress')
SUBNET_ID=$(cat describe-instance-$IP | jq -r '.Reservations[0].Instances[0].SubnetId')
DATA_VOLUME=$(cat describe-instance-$IP | jq -r '.Reservations[0].Instances[0].BlockDeviceMappings | .[] | select(.DeviceName == "/dev/xvdf").Ebs.VolumeId')
COMMITLOG_VOLUME=$(cat describe-instance-$IP | jq -r '.Reservations[0].Instances[0].BlockDeviceMappings | .[] | select(.DeviceName == "/dev/xvdg").Ebs.VolumeId')
SEC_GROUP_ID=$(cat describe-instance-$IP | jq -r '.Reservations[0].Instances[0].SecurityGroups[0].GroupId')
echo "Found $INSTANCE_COUNT instances."
if [ $INSTANCE_COUNT -ne "1" ]; then
    echo "Unexpected amount of instances found."
    exit 1
fi
echo "Replacing instance with ID: $OLD_INSTANCE_ID and IP: $OLD_INSTANCE_IP"
echo "SUBNET_ID: $SUBNET_ID"
echo "AZ: $AZ" 
echo "Security group ID: $SEC_GROUP_ID"
echo "Data volume ID: $DATA_VOLUME"
echo "Commitlog volume ID: $COMMITLOG_VOLUME"


echo "Terminating old instance."

echo "Enter 'yes' to continue."
CONFIRMATION=no
read CONFIRMATION
if [ "$CONFIRMATION" != "yes" ]; then
    echo "Instance replacement cancelled."
    exit 1
fi
aws ec2 terminate-instances --instance-ids $OLD_INSTANCE_ID
sleep 20


echo "Creating replacement instance."

USER_DATA="#taupage-ami-config
application_id: $APP_ID
application_version: $APP_VERSION
runtime: Docker
root: true
source: $IMAGE
scalyr_account_key: $SCALYR_KEY
mint_bucket: $MINT_BUCKET
networking: host
ports:
  7000: 7000
  7199: 7199
  8778: 8778
  9042: 9042
  9160: 9160
  61621: 61621
volumes:
  ebs:
    /dev/xvdf: cassandra-data-volume
    /dev/xvdg: cassandra-commitlog-volume
mounts:
  /var/cassandra/data/data:
    partition: /dev/xvdf
    erase_on_boot: false
    filesystem: ext4
  /var/cassandra/data/commitlog:
    partition: /dev/xvdg
    erase_on_boot: false
    filesystem: ext4
environment:
  CLUSTER_NAME: $CLUSTER_NAME
  OPSCENTER: $OPSCENTER
  TTL: 120
  DATA_DIR: /var/cassandra/data/data
  COMMIT_LOG_DIR: /var/cassandra/data/commitlog
  SNITCH: GossipingPropertyFileSnitch
  DATACENTER: AWS
  APPLICATION_ID: $APP_ID
  SEEDS: $SEEDS"

echo "${USER_DATA}" > userdata.yaml
echo "User data:"
cat userdata.yaml

echo "Creating new instance. Enter 'yes' to continue."
CONFIRMATION=no
read CONFIRMATION
if [ "$CONFIRMATION" != "yes" ]; then
    echo "Instance creation cancelled."
    exit 1
fi
aws ec2 run-instances \
                      --private-ip-address $IP \
                      --placement AvailabilityZone=$AZ \
                      --subnet-id $SUBNET_ID \
                      --image-id $TAUPAGE_AMI_ID \
                      --security-group-ids $SEC_GROUP_ID \
                      --iam-instance-profile Name=$INSTANCE_PROFILE_NAME \
                      --instance-type $INSTANCE_TYPE \
                      --count 1 \
                      --user-data file://userdata.yaml

aws ec2 describe-instances --filters Name=private-ip-address,Values=$IP > describe-instance-new-$IP
NEW_INSTANCE_ID=$(cat describe-instance-new-$IP | jq -r '.Reservations[0].Instances[0].InstanceId')
echo "Tagging new instance $NEW_INSTANCE_ID with name: $TAG."
aws ec2 create-tags --resources $NEW_INSTANCE_ID --tags Key=Name,Value=$TAG

echo "Done."












###
###

## IMAGE=registry.opensource.zalan.do/mop/stups-cassandra:2.0.17-p0-SNAPSHOT
 # static, hard-coded GTH and ITR seeds
 # dynamic AZ for rack.properties
 # dynamic LISTEN_ADDRESS for cassandra.yaml
 # dynamic SNITCH
 # no opscenter.

