# Cassandra EBS tools

The purpose of the scripts in this repository is to migrate data contained in a running Cassandra cluster
on AWS EC2 to AWS's EBS network storage. These operations are executed on a running cluster with no downtime.

Traditionally, Cassandra users were more inclined to use EC2 instance storage drives for their
Cassandra data and commit log directories. The instance store drives are SSDs physically
attached to the bare metal the EC2 instance runs on. This offers faster disk operations. However, 
recent [tests at Crowdstrike](https://www.youtube.com/watch?v=1R-mgOcOSd4) tests have proved that
great performance can also be achieved using EBS.

For the full list of optimizations necessary to ge the most out of EBS, check out the
[Crowdstrike slides](http://de.slideshare.net/jimplush/1-million-writes-per-second-on-60-nodes-with-cassandra-and-ebs).

When choosing the instance type your nodes will run on, it is important to select an EBS-optimized type.
At the time of this writing, the AWS console will display a wrong `EBS-optimized: false` attribute even
for instances that actually are [EBS-optimized](https://forums.aws.amazon.com/thread.jspa?messageID=620156). 
In addition to this, it is recommended to manually set 
[placement groups](http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/placement-groups.html)
for your instances to take advantage of higher network throughput and lower latencies.

Provisioned IOPS for EBS tend to be pretty expensive at the time, so creating larger disks and taking
advantage of the [3 IOPS/GiB](http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EBSVolumeTypes.html)
rule of EBS drives can be practical in some situations.

The two main scripts in the repo are:

    1. `switch-to-ebs.sh` and its remotely executed counterpart `switch-to-ebs-remote.sh` 
    2. `replace-node.sh`

The scripts make use of Zalando's [STUPS platform](stups.io) to simplify some steps in the process.
The Taupage AMI is used to automatically detect name-tagged EBS volumes and to attach them onto an instance.
Piu is used to get SSH access to an EC2 instance without a public IP address.
AWS CLI is used to create instances and other necessary resources such as instance profiles.

## switch-to-ebs.sh and switch-to-ebs-remote.sh
Switches an existing node from using an internal storage SSD to EBS. The EBS volumes need to be prepared
beforehand. Their IDs are then set as parameters in this script. The script attaches them, shuts down
Cassandra and copies the data and commit log directories from the instance store to the EBS volumes.

## replace-node.sh

Replaces an EC2 instance running a Cassandra node with a new one keeping the same EBS volumes and the data on them.
Needs to be run on only one node at a time. This is because of the way Taupage
[finds the EBS volume](https://github.com/zalando-stups/taupage/blob/87e671c466ad1109215d811733f4be8b151d9e17/runtime/opt/taupage/init.d/10-prepare-disks.py#L32)
it will mount. 
Currently this is done as follows:

    * Filter volumes belonging to instance's AZ
    * Filter volumes that have the same name tag as specified in Tauapage's config
    * Sort resulting volumes by instance ID and pick up the first one.

Therefore, in every moment only one volume of a specific name tag should be in detached mode. This is
easily achieved by simply terminating and respawning one instance at a time.

## Node repairs

After Cassandra was shut down on a node and the EBS or instance switching is finished, a
`nodetool repair --in-local-dc` should be executed to fix the inconsistencies caused by
the node being offline for a while.

