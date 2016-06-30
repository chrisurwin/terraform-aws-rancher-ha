#Terraform script to stand up Rancher HA cluster on AWS
This build on the work I did with Nick and the original can be download from https://github.com/nicksuckling/rancher-ha-server-aws/tree/develop

This script will setup HA on AWS with SSL terminating on an ELB with an appropriately configured variable file.
This was developed so that it should be simple for someone to stand up a Rancher HA server and test its functionality.

It will create the appropriate security groups, ELB, RDS and EC2 instances

#Usage
You will need to get the encryption key and the encrypted database password prior to using this script.
I would suggest standing up a test instance with the password that is required, generating the HA script and then using those values for a deployment.
As a test you can use the values below for database_password, database_encrypted_password and ha_encryption_key but I wouldn’t suggest running this as your production instance.

If you clone the repo and create a terraform.vars with the following entries populated, I’ve included sample data to ease the learning curve:

name = "rancher-ha"

ami_id = "ami-xxxxxxx"

instance_type = "t2.medium"

key_name = "aws_ssh_key_name"

rancher_ssl_cert = "certificate.crt"

rancher_ssl_key = "private.key"

rancher_ssl_chain = "ca_bundle.crt"

database_port = "3306"

database_name = "cattle"

database_username = "cattle"

database_password = "Password"

database_encrypted_password = "5174b161cc63834d652c2d1d85f9d86b:1ac7f229e9f240c1c2f6aa07d3c23e11" #this os Password encrypted using the encryption key below

ha_encryption_key = "N7sAQCFYvnOvrpStF5rHeDZfat9dFddhxxuI7T2Aykw="

scale_min_size = "3"

scale_max_size = "3"

scale_desired_size = "3"

ha_registration_url = "https://www.yoururl.com"

region = "eu-west-1"

vpc_id = "vpc-xxx"

az1 = "eu-west-1a"

az2 = "eu-west-1b"

az3 = "eu-west-1c"

