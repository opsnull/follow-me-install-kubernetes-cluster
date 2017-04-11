# 和我一步步部署 kubernetes 集群

本系列文档介绍使用二进制部署 `kubernetes` 集群的所有步骤，而不是使用 `kubeadm` 等自动化方式来部署集群；

在部署的过程中，将详细列出各组件的启动参数，它们的含义和可能遇到的问题。

部署完成后，你将理解系统各组件的交互原理，进而能快速解决实际问题。

所以本文档主要适合于那些有一定 kubernetes 基础，想通过一步步部署的方式来学习和了解系统配置、运行原理的人。

## 集群详情

+ Kubernetes 1.6.0
+ Docker  1.12.5
+ Etcd 3.1.5
+ Flanneld 0.7 vxlan 网络
+ TLS 认证通信 (所有组件，如 etcd、kubernetes master 和 node)
+ RBAC 授权
+ kublet TLS BootStrapping
+ kubedns、dashboard、heapster(influxdb、grafana)、EFK(elasticsearch、fluentd、kibana) 集群插件
+ 私有 registry 仓库，使用 ceph rgw 做存储，TLS + Basic 认证

## 步骤介绍

1. [创建 TLS 通信所需的证书和秘钥](01-TLS证书和秘钥.md)
2. [创建 kubeconfig 文件](02-kubeconfig文件.md)
3. [创建三节点的高可用 etcd 集群](03-高可用etcd集群.md)
4. [kubectl命令行工具](04-kubectl命令行工具.md)
5. [部署高可用 master 集群](05-部署高可用master集群.md)
6. [部署 node 节点](06-部署node节点.md)
7. [DNS 插件](07-dns-addon.md)
8. [Dashboard 插件](08-dashboard-addon.md)
9. [Heapster 插件](09-heapster-addon.md)
10. [EFK 插件](10-EFK-addons.md)
11. [创建私有 docker registry](11-创建私有docker-registry.md)