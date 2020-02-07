# Summary

## 和我一步步部署 kubernetes 集群

* [00.组件版本和配置策略](00.组件版本和配置策略.md)
* [01.初始化系统和全局变量](01.初始化系统和全局变量.md)
* [02.创建CA根证书和秘钥](02.创建CA根证书和秘钥.md)			
* [03.部署kubectl命令行工具](03.kubectl.md)			
* [04.部署etcd集群](04.etcd集群.md)				
* [05-1.部署master节点.md](05-1.master节点.md)
    * [05-2.apiserver集群](05-2.apiserver集群.md)
    * [05-3.controller-manager集群](05-3.controller-manager集群.md)	
    * [05-4.scheduler集群](05-4.scheduler集群.md)
* [06-1.部署woker节点](06-1.worker节点.md)			
    * [06-2.apiserver高可用之nginx代理](06-2.apiserver高可用.md)
    * [06-3.containerd](06-3.containerd.md)					
    * [06-4.kubelet](06-4.kubelet.md)				
    * [06-5.kube-proxy](06-5.kube-proxy.md)
    * [06-6.部署calico网络](06-6.calico.md)	
* [07.验证集群功能](07.验证集群功能.md)			
* [08-1.部署集群插件](08-1.部署集群插件.md)
    * [08-2.coredns插件](08-2.coredns插件.md)
    * [08-3.dashboard插件](08-3.dashboard插件.md)
    * [08-4.kube-prometheus插件](08-4.kube-prometheus插件.md)
	* [08-5.EFK插件](08-5.EFK插件.md)			
* [09.部署Docker-Registry](09.Registry.md)	
* [10.清理集群](10.清理集群.md)	
* [A.浏览器访问apiserver安全端口](A.浏览器访问kube-apiserver安全端口.md)
* [B.校验TLS证书](B.校验TLS证书.md)
* [C.部署metrics-server插件](C.metrics-server插件.md)
* [D.部署Harbor-Registry](D.部署Harbor-Registry.md)	

## 标签集合

* [标签](tags.md)