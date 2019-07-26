# ScyllaDB in AWS for OpenNMS

This is a Test Environment to evaluate the performance of a Production Ready [ScyllaDB](https://www.scylladb.com/) Cluster using their AWS AMI against latest [OpenNMS](https://www.opennms.com/).

The solution creates a 3 nodes ScyllaDB cluster using Storage Optimized Instances (i3).

The OpenNMS instance will have PostgreSQL 10 embedded, as well as a customized keyspace for Newts designed for Multi-DC in mind using TWCS for the compaction strategy, which is the recommended configuration for production.

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

* Wait for the ScyllaDB cluster and OpenNMS to be ready, prior execute the `metrics:stress` command.

  Use the `nodetool status` command to verify that all the required instances have joined the cluster.

  OpenNMS will wait only for the seed node to create the Newts keyspace and once the UI is available, it creates a requisition with 2 nodes: the OpenNMS server itself and the ScyllaDB seed node, to collect statistics through JMX and SNMP every 30 seconds. This will help with the analysis.

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

  For 100K:

  ```shell
  metrics:stress -r 60 -n 15000 -f 20 -g 5 -a 20 -s 1 -t 200 -i 300
  ```

  On a side note, injecting 50K samples per second means that OpenNMS is collecting data from 15 million unique samples every 5 minutes. For 100K, 30 million.

* Check the OpenNMS performance graphs to understand how it behaves. Additionally, you could check the Monitoring Tab on the AWS Console for each EC2 instance.

* Enjoy!

## Termination

To destroy all the resources:

```shell
terraform destroy
```

## Results

All the tests were performed using OpenNMS Horizon 24.1.2 with OpenJDK 11 and PostgreSQL 10 on the same server, running on a `c5.9xlarge` image. The reason for choosing this is because the impact of the `metrics:stress` command is lower than the normal `Collectd` operation, and the fact that OpenNMS is not doing any actual work besides running the stress test. For this reason, an administrator should have enough room for the extra work that OpenNMS would normally do, meaning the CPU load during these tests, should be as low as possible on the OpenNMS server.

For the ScyllaDB cluster, their custom AMIs auto-configured are used. Nothing has been tune on those instances.

The major bottleneck is the indexing operation associated with filling up the resource cache every time OpenNMS starts (regardless if there is data on ScyllaDB or not).

The in-memory implementation based on Guava performs a lot better and faster than its Redis counterpart. The size of the effective cache on Redis is 2 times the size of the in-memory implementation. Once the cache is filled up, the ring buffer starts to decrease but at an extremely slow rate, meaning it could take hours for the system to stabilize.

> *NOTE*: The tests with Redis were done only with the first use case.

> *WARNING*: The graphs obtained from the ScyllaDB node through JMX are not the same compared with Cassandra (ScyllaDB has fewer graphs).

### Use case 1: ScyllaDB cluster of 4 x i3.2xlarge (50K samples per second, in-memory cache)

* The cache size has 1.8 million entries (the limit was 2 million entries).
* The ring buffer with 8 million entries reaches the limit in 20min and remains full for about 4min dropping samples.
* After 4min, the ring buffer starts to decrease, but not as fast compared with the increasing rate.
* It takes about 90min to get the ring buffer empty (1GB in about 12min). It remains to inject at a higher rate while this is happening (~ 55K-60K).
* The time to fill up the cache is about 20min according to the index insert rate graph.
* When it is indexing, the sample insert rate is about 30% the expected one.
* CPU utilization of ScyllaDB nodes in about 75% after the indexing.

### Use case 2: ScyllaDB cluster of 8 x i3.2xlarge (50K samples per second, in-memory cache)

* The cache size has 1.8 million entries (the limit was 2 million entries).
* The ring buffer with 8 million entries reaches half the limit when it started to decrease (there were no dropped samples). Although, it would be risky to reduce the ring buffer size to guarantee 0 metric drops.
* After about 10min, the ring buffer starts to decrease faster compared with the increasing rate.
* It took about 5 min to empty the ring buffer (insert rate when over 100K per second temporarily).
* Doubling the resources on the cluster, reduced the times and buffer requirements by half.
* OpenNMS CPU under 40% all the time (close to that number during peeks, but stable at around 20%).
* ScyllaDB CPU up to 100% during peeks, then stable below 50% on each node.
* OpenNMS Network Bandwidth between 150Mbps to 200Mbps during indexing, then around to 85Mbps in average (with desired injection rate).
* For 50K Samples per second an 8 nodes cluster seems perfect.

We can easily conclude that the bigger the ScyllaDB cluster is, the faster it would be, reducing the pressure on the OpenNMS server and the cluster, especially when dealing with the resource cache.

In theory, it might be possible to reach 100K samples per second at expenses of pushing the ScyllaDB cluster, meaning the resource buffer behavior will be affected.

### Use case 3: ScyllaDB cluster of 16 x i3.2xlarge (100K samples per second, in-memory cache)

Considering the benefits of increasing the size of the ScyllaDB cluster, this time the injection rate has been duplicated. In terms of the OpenNMS configuration, the ring buffer was reduced by half.

* The cache size has 1.8 million entries (the limit was 2 million entries).
* The ring buffer with 4 million entries reaches a limit of 3.85 million entries aproximately the limit when it started to decrease (there were no dropped samples).
* After about 10min, the ring buffer starts to decrease faster compared with the increasing rate.
* It took about 8 min to empty the ring buffer (insert rate when over 150K per second temporarily).
* OpenNMS CPU under 40% all the time (close to that number during peeks, but stable at around 20%).
* ScyllaDB CPU up to 100% during peeks, then stable below 50% on each node.
* OpenNMS Network Bandwidth between 260Mbps to 360Mbps during indexing, then around to 170Mbps in average (with desired injection rate).
* For 100K Samples per second a 16 nodes cluster seems perfect.

By doubling the cluster size, we were able to reduce the ring buffer requirement by half.

In theory, it might be possible to reach 200K samples per second at expenses of pushing the ScyllaDB cluster, meaning the resource buffer behavior will be affected.
