#!/usr/bin/bash

# TLS Bootstrapping 使用的 Token，可以使用命令 head -c 16 /dev/urandom | od -An -t x | tr -d ' ' 生成
BOOTSTRAP_TOKEN="41f7e4ba8b7be874fcff18bf5cf41a7c"

# 最好使用 当前未用的网段 来定义服务网段和 Pod 网段

# 服务网段，部署前路由不可达，部署后集群内路由可达(kube-proxy 和 ipvs 保证)
SERVICE_CIDR="10.254.0.0/16"

# Pod 网段，建议 /16 段地址，部署前路由不可达，部署后集群内路由可达(flanneld 保证)
CLUSTER_CIDR="172.30.0.0/16"

# 服务端口范围 (NodePort Range)
export NODE_PORT_RANGE="8400-9000"

# 集群各机器 IP 数组
export NODE_IPS=(172.27.132.65 172.27.132.66 172.27.132.67)

# 集群各 IP 对应的 主机名数组
export NODE_NAMES=(kube-node1 kube-node2 kube-node3)

# kube-apiserver 节点 IP
export MASTER_IP=172.27.132.65

# kube-apiserver https 地址
export KUBE_APISERVER="https://${MASTER_IP}:6443"

# etcd 集群服务地址列表
export ETCD_ENDPOINTS="https://172.27.132.65:2379,https://172.27.132.66:2379,https://172.27.132.67:2379"

# etcd 集群间通信的 IP 和端口
export ETCD_NODES="kube-node1=https://172.27.132.65:2380,kube-node2=https://172.27.132.66:2380,kube-node3=https://172.27.132.67:2380"

# flanneld 网络配置前缀
export FLANNEL_ETCD_PREFIX="/kubernetes/network"

# kubernetes 服务 IP (一般是 SERVICE_CIDR 中第一个IP)
export CLUSTER_KUBERNETES_SVC_IP="10.254.0.1"

# 集群 DNS 服务 IP (从 SERVICE_CIDR 中预分配)
export CLUSTER_DNS_SVC_IP="10.254.0.2"

# 集群 DNS 域名
export CLUSTER_DNS_DOMAIN="cluster.local."

# 将二进制目录 /opt/k8s/bin 加到 PATH 中
export PATH=/opt/k8s/bin:$PATH