---
title: "Configure Amazon VPC CNI"
sidebar_position: 10
---

In this lab exercise, we'll start configuring the Amazon VPC CNI.

Let's review the existing VPC and availability zone configuration.

```bash
$ echo "The secondary subnet in AZ $AZ1 is $SECONDARY_SUBNET_1"
$ echo "The secondary subnet in AZ $AZ2 is $SECONDARY_SUBNET_2"
$ echo "The secondary subnet in AZ $AZ3 is $SECONDARY_SUBNET_3"
```

Set the `AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG` environment variable to *true* in the aws-node DaemonSet:

```bash
$ kubectl set env daemonset aws-node -n kube-system AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true
```

Create an ENIConfig custom resource for each subnet that you want to deploy pods in. Here is the ENIConfig configuration.

```file
modules/networking/custom-networking/provision/eniconfigs.yaml
```

Let's apply this to our cluster:

```bash
$ kubectl apply -k @{/workspace/modules/networking/custom-networking/provision}
```

Confirm that your `ENIConfig` objects were created:

```bash
$ kubectl get ENIConfigs
```

Update your aws-node DaemonSet to automatically apply the `ENIConfig` for an availability zone to any new Amazon EC2 nodes created in your cluster:

```bash
$ kubectl set env daemonset aws-node -n kube-system ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone
```