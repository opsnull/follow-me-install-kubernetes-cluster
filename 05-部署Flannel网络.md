<!-- toc -->

tags: flanneld

# 部署 Flannel 网络

kubernetes 要求集群内的 Node、Pod 能通过 Pod 网段互联互通，本文档介绍使用 Flannel 在**所有节点** (Master、Node) 上创建互联互通的 Pod 网段的步骤。

## 使用的变量

本文档用到的变量定义如下：

``` bash
$ # 导入用到的其它全局变量：ETCD_ENDPOINTS、FLANNEL_ETCD_PREFIX、CLUSTER_CIDR
$ source /root/local/bin/environment.sh
$
```

## 目录和文件

``` bash
$ sudo mkdir -p /etc/kubernetes/ssl
$ sudo cp ca.pem kubernetes.pem kubernetes-key.pem /etc/kubernetes/ssl
$
```

## 向 etcd 写入集群 Pod 网段信息

注意：本步骤只需在**第一次**部署 Flannel 网络时执行，后续在其它节点上部署 Flannel 时**无需**再写入该信息！

``` bash
$ /root/local/bin/etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=/etc/kubernetes/ssl/ca.pem \
  --cert-file=/etc/kubernetes/ssl/kubernetes.pem \
  --key-file=/etc/kubernetes/ssl/kubernetes-key.pem \
  set ${FLANNEL_ETCD_PREFIX}/config '{"Network":"'${CLUSTER_CIDR}'", "SubnetLen": 24, "Backend": {"Type": "vxlan"}}'
```

+ flanneld **目前版本 (v0.7.1) 不支持 etcd v3**，故使用 etcd v2 API 写入配置 key 和网段数据；
+ 写入的 Pod 网段(${CLUSTER_CIDR}，172.30.0.0/16) 必须与 kube-controller-manager 的 `--cluster-cidr` 选项值一致；


## 安装和配置 flanneld

### 下载 flanneld

``` bash
$ mkdir flannel
$ wget https://github.com/coreos/flannel/releases/download/v0.7.1/flannel-v0.7.1-linux-amd64.tar.gz
$ tar -xzvf flannel-v0.7.1-linux-amd64.tar.gz -C flannel
$ sudo cp flannel/{flanneld,mk-docker-opts.sh} /root/local/bin
$
```

### 创建 flanneld 的 systemd unit 文件

``` bash
$ cat > flanneld.service << EOF
[Unit]
Description=Flanneld overlay address etcd agent
After=network.target
After=network-online.target
Wants=network-online.target
After=etcd.service
Before=docker.service

[Service]
Type=notify
ExecStart=/root/local/bin/flanneld \\
  -etcd-cafile=/etc/kubernetes/ssl/ca.pem \\
  -etcd-certfile=/etc/kubernetes/ssl/kubernetes.pem \\
  -etcd-keyfile=/etc/kubernetes/ssl/kubernetes-key.pem \\
  -etcd-endpoints=${ETCD_ENDPOINTS} \\
  -etcd-prefix=${FLANNEL_ETCD_PREFIX}
ExecStartPost=/root/local/bin/mk-docker-opts.sh -k DOCKER_NETWORK_OPTIONS -d /run/flannel/docker
Restart=on-failure

[Install]
WantedBy=multi-user.target
RequiredBy=docker.service
EOF
```

+ etcd 集群启用了双向 TLS 认证，所以需要为 flanneld 指定与 etcd 集群通信的 CA 和秘钥；
+ mk-docker-opts.sh 脚本将分配给 flanneld 的 Pod 子网网段信息写入到 `/run/flannel/docker` 文件中，后续 docker 启动时使用这个文件中参数值设置 docker0 网桥；
+ `-iface` 选项值指定 flanneld 和其它 Node 通信的接口，如果机器有内、外网，则最好指定为内网接口；

完整 unit 见 [flanneld.service](https://github.com/opsnull/follow-me-install-kubernetes-cluster/blob/master/systemd/flanneld.service)

### 启动 flanneld

``` bash
$ sudo cp flanneld.service /etc/systemd/system/
$ sudo systemctl daemon-reload
$ sudo systemctl enable flanneld
$ sudo systemctl start flanneld
$ systemctl status flanneld
$
```

### 检查 flanneld 服务

``` bash
$ journalctl  -u flanneld |grep 'Lease acquired'
$ ifconfig flannel.1
$
```

### 检查分配给各 flanneld 的 Pod 网段信息

``` bash
$ # 查看集群 Pod 网段(/16)
$ /root/local/bin/etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=/etc/kubernetes/ssl/ca.pem \
  --cert-file=/etc/kubernetes/ssl/kubernetes.pem \
  --key-file=/etc/kubernetes/ssl/kubernetes-key.pem \
  get ${FLANNEL_ETCD_PREFIX}/config
{ "Network": "172.30.0.0/16", "SubnetLen": 24, "Backend": { "Type": "vxlan" } }
$ # 查看已分配的 Pod 子网段列表(/24)
$ /root/local/bin/etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=/etc/kubernetes/ssl/ca.pem \
  --cert-file=/etc/kubernetes/ssl/kubernetes.pem \
  --key-file=/etc/kubernetes/ssl/kubernetes-key.pem \
  ls ${FLANNEL_ETCD_PREFIX}/subnets
/kubernetes/network/subnets/172.30.19.0-24
$ # 查看某一 Pod 网段对应的 flanneld 进程监听的 IP 和网络参数
$ /root/local/bin/etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=/etc/kubernetes/ssl/ca.pem \
  --cert-file=/etc/kubernetes/ssl/kubernetes.pem \
  --key-file=/etc/kubernetes/ssl/kubernetes-key.pem \
  get ${FLANNEL_ETCD_PREFIX}/subnets/172.30.19.0-24
{"PublicIP":"10.64.3.7","BackendType":"vxlan","BackendData":{"VtepMAC":"d6:51:2e:80:5c:69"}}
```

### 确保各节点间 Pod 网段能互联互通

在**各节点上部署完** Flannel 后，查看已分配的 Pod 子网段列表(/24)

``` bash
$ /root/local/bin/etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=/etc/kubernetes/ssl/ca.pem \
  --cert-file=/etc/kubernetes/ssl/kubernetes.pem \
  --key-file=/etc/kubernetes/ssl/kubernetes-key.pem \
  ls ${FLANNEL_ETCD_PREFIX}/subnets
/kubernetes/network/subnets/172.30.19.0-24
/kubernetes/network/subnets/172.30.20.0-24
/kubernetes/network/subnets/172.30.21.0-24
```

当前三个节点分配的 Pod 网段分别是：172.30.19.0-24、172.30.20.0-24、172.30.21.0-24。

在各节点上分配 ping 这三个网段的网关地址，确保能通：

``` bash
$ ping 172.30.19.1
$ ping 172.30.20.2
$ ping 172.30.21.3
$
```