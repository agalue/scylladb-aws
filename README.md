# ScyllaDB in AWS for OpenNMS

This is a Test Environment to evaluate the performance of a Production Ready [ScyllaDB](https://www.scylladb.com/) Cluster using their own AWS AMI against latest [OpenNMS](https://www.opennms.com/).

The solution creates a 3 nodes ScyllaDB cluster using Storage Optimized Instances (i3).

The OpenNMS instance will have PostgreSQL 10 embedded, as well as a customized keyspace for Newts designed for Multi-DC in mind using TWCS for the compaction strategy, which is the recommended configuration for production).

## Installation and usage

* Make sure you have your AWS credentials on `~/.aws/credentials`, for example:

  ```ini
  [default]
  aws_access_key_id = XXXXXXXXXXXXXXXXX
  aws_secret_access_key = XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
  ```

* Install the Terraform binary from [terraform.io](https://www.terraform.io)

> *NOTE*: The templates requires Terraform version 0.12.x.

* Tweak the common settings on `vars.tf`, specially `aws_key_name`, `aws_private_key` and `aws_region`.

  If the region is changed, keep in mind that the ScyllaDB AMIs are not available on every region (click [here](https://www.scylladb.com/download/#aws) for more information). The OpenNMS instance is based on Amazon Linux 2, which is available on all regions (make sure to use the correct AMI ID).

  All the customizable settings are defined on `vars.tf`. Please do not change the other `.tf` files.

* Make sure you're able to create multiple instances of the chosen `i3` on your region (check `vars.tf`).

  For example, the limit for `i3.8xlarge` is 2, and you'll have to request an extension in order to create 3 instances or more.

* Execute the following commands from the repository's root directory (at the same level as the .tf files):

  ```shell
  terraform init
  terraform plan
  terraform apply -auto-approve
  ```

* Wait for the Cassandra cluster and OpenNMS to be ready, prior execute the `metrics:stress` command.

  Use the `nodetool status` command to verify that all the required instances have joined the cluster.

  OpenNMS will wait only for the seed node to create the Newts keyspace and once the UI is available, it creates a requisition with 2 nodes: the OpenNMS server itself and the Cassandra seed node, to collect statistics through JMX and SNMP every 30 seconds. This will help with the analysis.

* Connect to the Karaf Shell through SSH:

  From the OpenNMS instance:

  ```shell
  ssh -o ServerAliveInterval=10 -p 8101 admin@localhost
  ```

  Make sure it is running at least Karaf 4.1.5.

  You could SSH from your own machine. In this case, use the public IP of the OpenNMS server (look for it at the AWS console, or check the Terraform output).

* Execute the `metrics:stress` command. The following is an example to generate 50000 samples per second:

  ```shell
  metrics:stress -r 60 -n 15000 -f 20 -g 5 -a 10 -s 1 -t 200 -i 300
  ```

* Check the OpenNMS performance graphs to understand how it behaves. Additionally, you could check the Monitoring Tab on the AWS Console for each EC2 instance.

* Enjoy!

## Termination

To destroy all the resources:

```shell
terraform destroy
```
