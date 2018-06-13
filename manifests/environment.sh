#!/usr/bin/bash

# 生成 EncryptionConfig 所需的加密 key
ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

# 最好使用 主机未用的网段 来定义服务网段和 Pod 网段

# 服务网段 (Service CIDR），部署前路由不可达，部署后集群内使用IP:Port可达
SERVICE_CIDR="10.254.0.0/16"

# POD 网段 (Cluster CIDR），部署前路由不可达，**部署后**路由可达(flanneld保证)
CLUSTER_CIDR="172.30.0.0/16"

# 服务端口范围 (NodePort Range)
export NODE_PORT_RANGE="8400-9000"

# 集群所有机器 IP
export NODE_IPS=(172.27.129.105 172.27.129.111 172.27.129.112)

# 集群各 IP 对应的 主机名
export NODE_NAMES=(kube-node1 kube-node2 kube-node3)

# etcd 集群服务地址列表
export ETCD_ENDPOINTS="https://172.27.129.105:2379,https://172.27.129.111:2379,https://172.27.129.112:2379"

# etcd 集群间通信的IP和端口
export ETCD_NODES="kube-node1=https://172.27.129.105:2380,kube-node2=https://172.27.129.111:2380,kube-node3=https://172.27.129.112:2380"

# flanneld 网络配置前缀
export FLANNEL_ETCD_PREFIX="/kubernetes/network"

# kubernetes 服务 IP (一般是 SERVICE_CIDR 中第一个IP)
export CLUSTER_KUBERNETES_SVC_IP="10.254.0.1"

# 集群 DNS 服务 IP (从 SERVICE_CIDR 中预分配)
export CLUSTER_DNS_SVC_IP="10.254.0.2"

# 集群 DNS 域名
export CLUSTER_DNS_DOMAIN="cluster.local."

# 将二进制目录 /opt/k8s/bin 加入到 PATH 中
export PATH=/opt/k8s/bin:$PATH