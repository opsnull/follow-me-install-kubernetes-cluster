# 组件版本和集群环境介绍

## 集群各组件的版本

+ Kubernetes 1.6.1
+ Docker  17.04.0-ce
+ Etcd 3.1.5
+ Flanneld 0.7 vxlan 网络
+ TLS 认证通信 (所有组件，如 etcd、kubernetes master 和 node)
+ RBAC 授权
+ kublet TLS BootStrapping
+ kubedns、dashboard、heapster (influxdb、grafana)、EFK (elasticsearch、fluentd、kibana) 插件
+ 私有 docker registry，使用 ceph rgw 后端存储，TLS + HTTP Basic 认证

## 集群机器情况

+ 10.64.3.7
+ 10.64.3.8
+ 10.66.3.86

本着测试的目的，etcd 集群、kubernetes master 集群、kubernetes node 集群均使用这三台机器；

## 全局变量定义

``` bash
# 服务网段 (Service CIDR），部署前必须路由不可达
SERVICE_CIDR="10.254.0.0/16"

# POD 网段 (Cluster CIDR），必须路由可达(flanneld保证)
CLUSTER_CIDR="172.30.0.0/16"

# 服务端口范围 (NodePort CIDR)
NODE_PORT_RANGE="8400-9000"

# etcd 集群监客户端连接的地列表，为保证高可至少指定两台机器
ETCD_ENDPOINTS="https://10.64.3.7:2379,https://10.64.3.8:2379,https://10.66.3.86:2379"

# flanneld 从 etcd 集群获取网络配置的 key
FLANNEL_ETCD_PREFIX="/kubernetes/network"

# kubernetes 服务IP, (一般是 SERVICE_CIDR 中第一个IP)
CLUSTER_KUBERNETES_SVC_IP="10.254.0.1"

# 集群 DNS 服务 IP (从 SERVICE_CIDR 中预分配)
CLUSTER_DNS_SVC_IP="10.254.0.2"

# 集群 DNS 域名
CLUSTER_DNS_DOMAIN="cluster.local."
```

+ 需要根据**实际情况修改**这些变量值；
+ 打包后的变量定义见文件：[environment.sh](./manifests/environment.sh)，后续部署时会**提示导入**这个文中的环境变量；

## 分发全局变量定义脚本

把全局变量定义脚本 [environment.sh](./manifests/environment.sh) 拷贝到**所有**机器的 `/root/local/bin` 目录下备用。

``` bash
$ cp environment.sh /root/local/bin
$
```