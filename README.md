# 和我一步步部署 kubernetes 集群

![dashboard](./images/dashboard.png)

本系列文档介绍使用二进制部署 `kubernetes` 集群的所有步骤，而不是使用 `kubeadm` 等自动化方式来部署集群；

在部署的过程中，将详细列出各组件的启动参数，它们的含义和可能遇到的问题。

部署完成后，你将理解系统各组件的交互原理，进而能快速解决实际问题。

所以本文档主要适合于那些有一定 kubernetes 基础，想通过一步步部署的方式来学习和了解系统配置、运行原理的人。

## 集群详情

+ Kubernetes 1.6.1
+ Docker  17.04.0-ce
+ Etcd 3.1.5
+ Flanneld 0.7 vxlan 网络
+ TLS 认证通信 (所有组件，如 etcd、kubernetes master 和 node)
+ RBAC 授权
+ kublet TLS BootStrapping
+ kubedns、dashboard、heapster(influxdb、grafana)、EFK(elasticsearch、fluentd、kibana) 集群插件
+ 私有 registry 仓库，使用 ceph rgw 做存储，TLS + Basic 认证

## 步骤介绍

1. [创建 TLS 通信所需的证书和秘钥](01-TLS证书和秘钥.md)
1. [创建 kubeconfig 文件](02-kubeconfig文件.md)
1. [创建三节点的高可用 etcd 集群](03-高可用etcd集群.md)
1. [kubectl命令行工具](04-kubectl命令行工具.md)
1. [部署高可用 master 集群](05-部署高可用master集群.md)
1. [部署 node 节点](06-部署node节点.md)
1. [DNS 插件](07-dns-addon.md)
1. [Dashboard 插件](08-dashboard-addon.md)
1. [Heapster 插件](09-heapster-addon.md)
1. [EFK 插件](10-EFK-addons.md)
1. [创建私有 docker registry](11-创建私有docker-registry.md)

## 注意

1. 由于启用了 TLS 双向认证、RBAC 授权等严格的安全机制，建议**从头开始部署**，而不要从中间开始，否则可能会认证、授权等失败！
1. 本文档将**随着各组件的更新而更新**，有任何问题欢迎提 issue！

## 版权

Copyright 2017 zhangjun(geekard@qq.com)

Apache License 2.0，详情见 [LICENSE](LICENSE) 文件。

希望对你有帮助！