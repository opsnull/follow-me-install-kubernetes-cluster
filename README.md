# 和我一步步部署 kubernetes 集群

![dashboard-home](./images/dashboard-home.png)

本系列文档介绍使用二进制部署最新 `kubernetes v1.10.2` 集群的所有步骤，而不是使用 `kubeadm` 等自动化方式来部署集群。

在部署的过程中，将详细列出各组件的启动参数，它们的含义和可能遇到的问题。

部署完成后，你将理解系统各组件的交互原理，进而能快速解决实际问题。

所以本文档主要适合于那些有一定 kubernetes 基础，想通过一步步部署的方式来学习和了解系统配置、运行原理的人。

本系列系文档适用于 `CentOS 7`、`Ubuntu 16.04` 及以上版本系统，**随着各组件的更新而更新**，有任何问题欢迎提 issue！

由于启用了 `TLS` 双向认证、`RBAC` 授权等严格的安全机制，建议**从头开始部署**，否则可能会认证、授权等失败！

## 步骤列表

1. [组件版本和集群环境](01-组件版本和集群环境.md)
1. [创建 CA 证书和秘钥](02-创建CA证书和秘钥.md)
1. [部署高可用 Etcd 集群](03-部署高可用Etcd集群.md)
1. [下载和配置 Kubectl 命令行工具](04-部署Kubectl命令行工具.md)
1. [配置 Flannel 网络](05-部署Flannel网络.md)
1. [部署 Master 节点](06-部署Master节点.md)
1. [部署 Node 节点](07-部署Node节点.md)
1. [部署 DNS 插件](08-部署DNS插件.md)
1. [部署 Dashboard 插件](09-部署Dashboard插件.md)
1. [部署 Heapster 插件](10-部署Heapster插件.md)
1. [部署 EFK 插件](11-部署EFK插件.md)
1. [部署 Docker Registry](12-部署Docker-Registry.md)
1. [部署 Harbor 私有仓库](13-部署harbor私有仓库.md)
1. [清理集群](14-清理集群.md)

## 在线阅读

+ 建议：[GitBook](https://k8s-install.opsnull.com/)
+ [Github](https://www.gitbook.com/book/opsnull/follow-me-install-kubernetes-cluster)

## 电子书

+ pdf 格式 [下载](https://www.gitbook.com/download/pdf/book/opsnull/follow-me-install-kubernetes-cluster)
+ epub 格式 [下载](https://www.gitbook.com/download/epub/book/opsnull/follow-me-install-kubernetes-cluster)

## 版权

Copyright 2017-2018 zhangjun (geekard@qq.com)

Apache License 2.0，详情见 [LICENSE](LICENSE) 文件。

转载时请保证内容完整，并注明来源！

## 打赏

如果你觉得这份文档对你有帮助，请微信扫描下方的二维码进行捐赠，加油后的 opsnull 将会和你分享更多的原创教程，谢谢！

<p align="center">
  <img src="https://github.com/opsnull/follow-me-install-kubernetes-cluster/blob/master/images/weixin_qr.jpg?raw=true" alt="weixin_qr.jpg"/>
</p>