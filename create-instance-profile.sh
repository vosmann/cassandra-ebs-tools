aws iam create-instance-profile --instance-profile-name cassandra-profile
aws iam add-role-to-instance-profile --instance-profile-name cassandra-profile --role-name cassandra-transfer
