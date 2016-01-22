INSTANCE_ID=$1
INSTANCE_IP=$2
DATA_ID=$3
COMMITLOG_ID=$4
USERNAME=$5

echo "Will abort if any command fails."
set -e 
set -o pipefail

echo "Attaching EBS volumes."
aws ec2 attach-volume --volume-id $DATA_ID --instance-id $INSTANCE_ID --device /dev/xvdf
aws ec2 attach-volume --volume-id $COMMITLOG_ID --instance-id $INSTANCE_ID --device /dev/xvdg

piu -c ~/other-piu.yaml $INSTANCE_IP "Attach EBS drive, copy sstables, switch Casssandra to use it."
echo "Running script remotely."
# -t to force pseudo-tty allocation (remote interactive shell)
ssh -t $USERNAME@$INSTANCE_IP 'bash -s' < switch-to-ebs-remote.sh

