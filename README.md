# 和我一步步部署 kubernetes 集群

![dashboard-home](./images/dashboard-home.png)

本系列文档介绍使用二进制部署 `kubernetes v1.22.1` 集群的所有步骤（Hard-Way 模式）。

在部署的过程中，将详细列出各组件的启动参数，它们的含义和可能遇到的问题。

部署完成后，你将理解系统各组件的交互原理，进而能快速解决实际问题。

所以本文档主要适合于那些有一定 kubernetes 基础，想通过一步步部署的方式来学习和了解系统配置、运行原理的人。

本系列系文档适用于 `CentOS 7` 及以上版本系统，**随着各组件的更新而更新**，有任何问题欢迎提 issue！

由于启用了 `x509` 证书双向认证、`RBAC` 授权等严格的安全机制，建议**从头开始部署**，否则可能会认证、授权等失败！

从 v1.16.x 版本开始，本文档做了如下调整：

1. 容器运行时：用 containerd 替换 docker，更加简单、健壮；相应的命令行工具为 crictl；
2. Pod 网络：用 calico 替换 flannel 实现 Pod 互通，支持更大规模的集群；

新增指标监控系统：使用主流的 Prometheus、Grafana 技术栈实现集群指标采集和监控；

如果想继续使用 docker 和 flannel，请参考附件文档。

## 历史版本

+ [v1.6.2](https://github.com/opsnull/follow-me-install-kubernetes-cluster/tree/v1.6.2)：已停止更新；
+ [v1.8.x](https://github.com/opsnull/follow-me-install-kubernetes-cluster/tree/v1.8.x)：已停止更新；
+ [v1.10.x](https://github.com/opsnull/follow-me-install-kubernetes-cluster/tree/v1.10.x)：已停止更新；
+ [v1.12.x](https://github.com/opsnull/follow-me-install-kubernetes-cluster/tree/v1.12.x)：已停止更新；
+ [v1.14.x](https://github.com/opsnull/follow-me-install-kubernetes-cluster/tree/v1.14.x)：继续更新；

## 步骤列表

1. [00.组件版本和配置策略](00.组件版本和配置策略.md)
1. [01.初始化系统和全局变量](01.初始化系统和全局变量.md)
1. [02.创建CA根证书和秘钥](02.创建CA根证书和秘钥.md)   
1. [03.部署kubectl命令行工具](03.kubectl.md)   
1. [04.部署etcd集群](04.etcd集群.md)    
1. [05-1.部署master节点.md](05-1.master节点.md)
    1. [05-2.apiserver集群](05-2.apiserver集群.md)
    1. [05-3.controller-manager集群](05-3.controller-manager集群.md) 
    1. [05-4.scheduler集群](05-4.scheduler集群.md)
1. [06-1.部署woker节点](06-1.worker节点.md)   
    1. [06-2.apiserver高可用之nginx代理](06-2.apiserver高可用.md)
    1. [06-3.containerd](06-3.containerd.md)     
    1. [06-4.kubelet](06-4.kubelet.md)    
    1. [06-5.kube-proxy](06-5.kube-proxy.md)
    1. [06-6.部署calico网络](06-6.calico.md) 
1. [07.验证集群功能](07.验证集群功能.md)   
1. [08-1.部署集群插件](08-1.部署集群插件.md)
    1. [08-2.coredns插件](08-2.coredns插件.md)
    1. [08-3.dashboard插件](08-3.dashboard插件.md)
    1. [08-4.kube-prometheus插件](08-4.kube-prometheus插件.md)
    1. [08-5.EFK插件](08-5.EFK插件.md)   
1. [09.部署Docker-Registry](09.Registry.md) 
1. [10.清理集群](10.清理集群.md) 
1. [A.浏览器访问apiserver安全端口](A.浏览器访问kube-apiserver安全端口.md)
1. [B.校验TLS证书](B.校验TLS证书.md)
1. [C.部署metrics-server插件](C.metrics-server插件.md)
1. [D.部署Harbor-Registry](D.部署Harbor-Registry.md) 

## 在线阅读

+ 建议：[GitBook](https://k8s-install.opsnull.com/)
+ [Github](https://www.gitbook.com/book/opsnull/follow-me-install-kubernetes-cluster)

## 电子书

+ pdf 格式 [下载](https://www.gitbook.com/download/pdf/book/opsnull/follow-me-install-kubernetes-cluster)
+ epub 格式 [下载](https://www.gitbook.com/download/epub/book/opsnull/follow-me-install-kubernetes-cluster)

## 打赏

如果你觉得这份文档对你有帮助，请微信扫描下方的二维码进行捐赠，加油后的 opsnull 将会和你分享更多的原创教程，谢谢！

<p align="center">
  <img src="https://github.com/opsnull/follow-me-install-kubernetes-cluster/blob/master/images/weixin_qr.jpg?raw=true" alt="weixin_qr.jpg"/>
</p>

## 广告位

## 版权

Copyright 2017-2020 zhangjun (geekard@qq.com)

知识共享 署名-非商业性使用-相同方式共享 4.0（CC BY-NC-SA 4.0），详情见 [LICENSE](LICENSE) 文件。
