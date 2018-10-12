# Kubernetes 大规模集群

Kubernetes v1.6-v1.11 单集群最大支持 5000 个节点，也就是说 Kubernetes 最新稳定版的单个集群支持
不超过 5000 个节点
不超过 150000 个 Pod
不超过 300000 个容器
每台 Node 上不超过 100 个 Pod

## 公有云配额

对于公有云上的 Kubernetes 集群，规模大了之后很容器碰到配额问题，需要提前在云平台上增大配额。这些需要增大的配额包括
虚拟机个数
vCPU 个数
内网 IP 地址个数
公网 IP 地址个数
安全组条数
路由表条数
持久化存储大小

## Etcd 存储

除了常规的 Etcd 高可用集群配置、使用 SSD 存储等，还需要为 Events 配置单独的 Etcd 集群。即部署两套独立的 Etcd 集群，并配置 kube-apiserver
--etcd-servers="http://etcd1:2379,http://etcd2:2379,http://etcd3:2379" --etcd-servers-overrides="/events#http://etcd4:2379,http://etcd5:2379,http://etcd6:2379"
另外，Etcd 默认存储限制为 2GB，可以通过 --quota-backend-bytes 选项增大。

## Master 节点大小

可以参考 AWS 配置 Master 节点的大小：
1-5 nodes: m3.medium
6-10 nodes: m3.large
11-100 nodes: m3.xlarge
101-250 nodes: m3.2xlarge
251-500 nodes: c4.4xlarge
more than 500 nodes: c4.8xlarge

## 为扩展分配更多资源

Kubernetes 集群内的扩展也需要分配更多的资源，包括为这些 Pod 分配更大的 CPU 和内存以及增大容器副本数量等。当 Node 本身的容量太小时，还需要增大 Node 本身的 CPU 和内存（特别是在公有云平台上）。
以下扩展服务需要增大 CPU 和内存：
DNS (kube-dns or CoreDNS)
InfluxDB and Grafana
Kibana
FluentD with ElasticSearch Plugin
FluentD with GCP Plugin
以下扩展服务需要增大副本数：
elasticsearch
DNS (kube-dns or CoreDNS)
另外，为了保证多个副本分散调度到不同的 Node 上，需要为容器配置 AntiAffinity。比如，对 kube-dns，可以增加如下的配置：
affinity:
 podAntiAffinity:
   requiredDuringSchedulingIgnoredDuringExecution:
   - weight: 100
     labelSelector:
       matchExpressions:
       - key: k8s-app
         operator: In
         values:
         - kube-dns
     topologyKey: kubernetes.io/hostname

## Kube-apiserver 配置

设置 --max-requests-inflight=3000
设置 --max-mutating-requests-inflight=1000

## Kube-scheduler 配置

设置 --kube-api-qps=100
Kube-controller-manager 配置
设置 --kube-api-qps=100
设置 --kube-api-burst=100

## Kubelet 配置

设置 --image-pull-progress-deadline=30m
设置 --serialize-image-pulls=false（需要 Docker 使用 overlay2 ）
Kubelet 单节点允许运行的最大 Pod 数：--max-pods=110（默认是 110，可以根据实际需要设置）

## Docker 配置

设置 max-concurrent-downloads=10
使用 SSD 存储 graph=/ssd-storage-path
预加载 pause 镜像，比如 docker image save -o /opt/preloaded_docker_images.tar 和 docker image load -i /opt/preloaded_docker_images.tar

## 节点配置

增大内核选项配置 /etc/sysctl.conf：
fs.file-max=1000000

net.ipv4.ip_forward=1
net.netfilter.nf_conntrack_max=10485760
net.netfilter.nf_conntrack_tcp_timeout_established=300
net.netfilter.nf_conntrack_buckets=655360
net.core.netdev_max_backlog=10000

net.ipv4.neigh.default.gc_thresh1=1024
net.ipv4.neigh.default.gc_thresh2=4096
net.ipv4.neigh.default.gc_thresh3=8192

net.netfilter.nf_conntrack_max=10485760
net.netfilter.nf_conntrack_tcp_timeout_established=300
net.netfilter.nf_conntrack_buckets=655360
net.core.netdev_max_backlog=10000

fs.inotify.max_user_instances=524288
fs.inotify.max_user_watches=524288

## 应用配置

在运行 Pod 的时候也需要注意遵循一些最佳实践，比如
为容器设置资源请求和限制
spec.containers[].resources.limits.cpu
spec.containers[].resources.limits.memory
spec.containers[].resources.requests.cpu
spec.containers[].resources.requests.memory
spec.containers[].resources.limits.ephemeral-storage
spec.containers[].resources.requests.ephemeral-storage
对关键应用使用 PodDisruptionBudget、nodeAffinity、podAffinity 和 podAntiAffinity 等保护
尽量使用控制器来管理容器（如 Deployment、StatefulSet、DaemonSet、Job 等）