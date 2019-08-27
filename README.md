# 和我一步步部署 kubernetes 集群

![dashboard-home](./images/dashboard-home.png)

本系列文档介绍使用二进制部署最新 `kubernetes v1.14.2` 集群的所有步骤，而不是使用 `kubeadm` 等自动化方式来部署集群。

在部署的过程中，将详细列出各组件的启动参数，它们的含义和可能遇到的问题。

部署完成后，你将理解系统各组件的交互原理，进而能快速解决实际问题。

所以本文档主要适合于那些有一定 kubernetes 基础，想通过一步步部署的方式来学习和了解系统配置、运行原理的人。

本系列系文档适用于 `CentOS 7`、`Ubuntu 16.04` 及以上版本系统，**随着各组件的更新而更新**，有任何问题欢迎提 issue！

由于启用了 `x509` 证书双向认证、`RBAC` 授权等严格的安全机制，建议**从头开始部署**，否则可能会认证、授权等失败！

## 历史版本

+ [v1.6.2](https://github.com/opsnull/follow-me-install-kubernetes-cluster/tree/v1.6.2)：已停止更新；
+ [v1.8.x](https://github.com/opsnull/follow-me-install-kubernetes-cluster/tree/v1.8.x)：继续更新；
+ [v1.10.x](https://github.com/opsnull/follow-me-install-kubernetes-cluster/tree/v1.10.x)：继续更新；
+ [v1.12.x](https://github.com/opsnull/follow-me-install-kubernetes-cluster/tree/v1.12.x)：继续更新；

## 步骤列表

1. [00.组件版本和配置策略](00.组件版本和配置策略.md)
1. [01.系统初始化和全局变量](01.系统初始化和全局变量.md)
1. [02.创建CA证书和秘钥](02.创建CA证书和秘钥.md)			
1. [03.部署kubectl命令行工具](03.部署kubectl命令行工具.md)			
1. [04.部署etcd集群](04.部署etcd集群.md)				
1. [05.部署flannel网络](05.部署flannel网络.md)		
1. [06.apiserver高可用之nginx代理.md](06-0.apiserver高可用之nginx代理.md)
1. [06-1.部署master节点](06-1.部署master节点.md)
    1. [06-2.apiserver集群](06-2.apiserver集群.md)	
    1. [06-3.controller-manager集群](06-3.controller-manager集群.md)
    1. [06-4.scheduler集群](06-4.scheduler集群.md)		
1. [07.部署worker节点](07-0.部署worker节点.md)
    1. [07-1.docker](07-1.docker.md)					
    1. [07-2.kubelet](07-2.kubelet.md)				
    1. [07-3.kube-proxy](07-3.kube-proxy.md)			
1. [08.验证集群功能](08.验证集群功能.md)			
1. [09.部署集群插件](09-0.部署集群插件.md)
    1. [09-1.dns插件](09-1.dns插件.md)
    1. [09-2.dashboard插件](09-2.dashboard插件.md)
    1. [09-3.metrics-server插件](09-3.metrics-server插件.md)
    1. [09-4.EFK插件](09-4.EFK插件.md)			
1. [10.部署Docker-Registry](10.部署Docker-Registry.md)	
1. [11.部署Harbor-Registry](11.部署Harbor-Registry.md)	
1. [12.清理集群](12.清理集群.md)
1. [A.浏览器访问apiserver安全端口](A.浏览器访问kube-apiserver安全端口.md)
1. [B.校验TLS证书](B.校验TLS证书.md)

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

## 广告

维护一个开源项目需要很多时间和精力，请点击下面的赞助商广告，给 opsnull 加杯 coffee 吧，谢谢！

***

### Kubernetes 微服务管理面板之 Kuboard （赞助推广）

相较于 Kubernetes Dashboard，Kuboard 是一款操作型（可以直接在界面中编辑工作负载，无需编写 YAML 文件）的管理面板。同时，Kuboard 依据微服务参考架构对名称空间的工作负载进行分层显示，是一款基于 Kubernetes 的微服务管理面板。

+ [Kuboard 官网](https://www.kuboard.cn)
+ [在线体验(只读)](http://demo.kuboard.cn/#/dashboard?k8sToken=eyJhbGciOiJSUzI1NiIsImtpZCI6IiJ9.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJrdWJlLXN5c3RlbSIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VjcmV0Lm5hbWUiOiJrdWJvYXJkLXZpZXdlci10b2tlbi1mdGw0diIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VydmljZS1hY2NvdW50Lm5hbWUiOiJrdWJvYXJkLXZpZXdlciIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VydmljZS1hY2NvdW50LnVpZCI6ImE1YWFiMmQxLTQxMjYtNDU5Yi1hZmNhLTkyYzMwZDk0NTQzNSIsInN1YiI6InN5c3RlbTpzZXJ2aWNlYWNjb3VudDprdWJlLXN5c3RlbTprdWJvYXJkLXZpZXdlciJ9.eYqN3FLIT6xs0-lm8AidZtaiuHeX70QTn9FhJglhEyh5dlyMU5lo8UtR-h1OY8sTSeYdYKJAS83-9SUObKQhp6XNmRgOYAfZblKUy4mvbGVQ3dn_qnzxYxt6zdGCwIY7E34eNNd9IjMF7G_Y4eJLWE7NvkSB1O8zbdn8En9rQXv_xJ9-ugCyr4CYB1lDGuZl3CIXgQ1FWcQdUBrxTT95tzcNTB0l6OUOGhRxOfw-RyIOST83GV5U0iVzxnD4sjgSaJefvCU-BmwXgpxAwRVhFyHEziXXa0CuZfBfJbmnQW308B4wocr4QDm6Nvmli1P3B6Yo9-HNF__d2hCwZEr7eg)

![kuboard](./images/kuboard.png)

***

## 版权

Copyright 2017-2019 zhangjun (geekard@qq.com)

知识共享 署名-非商业性使用-相同方式共享 4.0（CC BY-NC-SA 4.0），详情见 [LICENSE](LICENSE) 文件。