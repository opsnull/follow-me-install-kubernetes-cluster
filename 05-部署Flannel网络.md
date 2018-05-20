<!-- toc -->

tags: flanneld

# 部署 Flannel 网络

kubernetes 要求集群内各节点能通过 Pod 网段互联互通，本文档介绍使用 Flannel 在**所有节点** (Master、Node) 上创建互联互通的 Pod 网段的步骤。

## 使用的变量

本文档用到的变量定义如下：

``` bash
$ export NODE_IP=10.64.3.7 # 当前部署节点的 IP
$ # 导入用到的其它全局变量：ETCD_ENDPOINTS、FLANNEL_ETCD_PREFIX、CLUSTER_CIDR
$ source /root/local/bin/environment.sh
$
```

## 创建 TLS 秘钥和证书

etcd 集群启用了双向 TLS 认证，所以需要为 flanneld 指定与 etcd 集群通信的 CA 和秘钥。

创建 flanneld 证书签名请求：

``` bash
$ cat > flanneld-csr.json <<EOF
{
  "CN": "flanneld",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF
```

+ hosts 字段为空；所有主机都可以使用。

生成 flanneld 证书和私钥：

``` bash
$ cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
  -ca-key=/etc/kubernetes/ssl/ca-key.pem \
  -config=/etc/kubernetes/ssl/ca-config.json \
  -profile=kubernetes flanneld-csr.json | cfssljson -bare flanneld
$ ls flanneld*
flanneld.csr  flanneld-csr.json  flanneld-key.pem flanneld.pem
$ sudo mkdir -p /etc/flanneld/ssl     ### 每个节点都创建；
$ sudo mv flanneld*.pem /etc/flanneld/ssl  
$ scp /etc/flanneld/ssl/flanneld*.pem 192.168.0.131:/etc/flanneld/ssl/    ### 拷贝至另外两个节点上。
$ scp /etc/flanneld/ssl/flanneld*.pem 192.168.0.132:/etc/flanneld/ssl/
$ rm flanneld.csr  flanneld-csr.json
```

## 向 etcd 写入集群 Pod 网段信息

注意：本步骤只需在**第一次**部署 Flannel 网络时执行，后续在其它节点上部署 Flannel 时**无需**再写入该信息！

``` bash
$ /root/local/bin/etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=/etc/kubernetes/ssl/ca.pem \
  --cert-file=/etc/flanneld/ssl/flanneld.pem \
  --key-file=/etc/flanneld/ssl/flanneld-key.pem \
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
  -etcd-certfile=/etc/flanneld/ssl/flanneld.pem \\
  -etcd-keyfile=/etc/flanneld/ssl/flanneld-key.pem \\
  -etcd-endpoints=${ETCD_ENDPOINTS} \\
  -etcd-prefix=${FLANNEL_ETCD_PREFIX}
ExecStartPost=/root/local/bin/mk-docker-opts.sh -k DOCKER_NETWORK_OPTIONS -d /run/flannel/docker
Restart=on-failure

[Install]
WantedBy=multi-user.target
RequiredBy=docker.service
EOF
```

+ mk-docker-opts.sh 脚本将分配给 flanneld 的 Pod 子网网段信息写入到 `/run/flannel/docker` 文件中，后续 docker 启动时使用这个文件中参数值设置 docker0 网桥；
+ flanneld 使用系统缺省路由所在的接口和其它节点通信，对于有多个网络接口的机器（如，内网和公网），可以用 `--iface` 选项值指定通信接口(上面的 systemd unit 文件没指定这个选项)，如本着 Vagrant + Virtualbox，就要指定`--iface=enp0s8`；

完整 unit 见 [flanneld.service](https://github.com/opsnull/follow-me-install-kubernetes-cluster/blob/master/systemd/flanneld.service)

### 启动 flanneld

``` bash
$ sudo mv flanneld.service /etc/systemd/system/
$ scp /etc/systemd/system/flanneld.service  192.168.0.131:/etc/systemd/system/   ###拷贝至其他节点
$ scp /etc/systemd/system/flanneld.service  192.168.0.132:/etc/systemd/system/
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
  --cert-file=/etc/flanneld/ssl/flanneld.pem \
  --key-file=/etc/flanneld/ssl/flanneld-key.pem \
  get ${FLANNEL_ETCD_PREFIX}/config
{ "Network": "172.30.0.0/16", "SubnetLen": 24, "Backend": { "Type": "vxlan" } }
$ # 查看已分配的 Pod 子网段列表(/24)
$ /root/local/bin/etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=/etc/kubernetes/ssl/ca.pem \
  --cert-file=/etc/flanneld/ssl/flanneld.pem \
  --key-file=/etc/flanneld/ssl/flanneld-key.pem \
  ls ${FLANNEL_ETCD_PREFIX}/subnets
/kubernetes/network/subnets/172.30.60.0-24
/kubernetes/network/subnets/172.30.43.0-24
/kubernetes/network/subnets/172.30.88.0-24
$ # 查看某一 Pod 网段对应的 flanneld 进程监听的 IP 和网络参数
$ /root/local/bin/etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=/etc/kubernetes/ssl/ca.pem \
  --cert-file=/etc/flanneld/ssl/flanneld.pem \
  --key-file=/etc/flanneld/ssl/flanneld-key.pem \
  get ${FLANNEL_ETCD_PREFIX}/subnets/172.30.60.0-24    ###腰根据上面查到的Pod子网信息替换该网段。
{"PublicIP":"192.168.0.130","BackendType":"vxlan","BackendData":{"VtepMAC":"d6:51:2e:80:5c:69"}}
```

### 确保各节点间 Pod 网段能互联互通

在**各节点上部署完** Flannel 后，查看已分配的 Pod 子网段列表(/24)

``` bash
$ /root/local/bin/etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=/etc/kubernetes/ssl/ca.pem \
  --cert-file=/etc/flanneld/ssl/flanneld.pem \
  --key-file=/etc/flanneld/ssl/flanneld-key.pem \
  ls ${FLANNEL_ETCD_PREFIX}/subnets
/kubernetes/network/subnets/172.30.60.0-24
/kubernetes/network/subnets/172.30.43.0-24
/kubernetes/network/subnets/172.30.88.0-24
```

当前三个节点分配的 Pod 网段分别是：172.30.60.0-24、172.30.43.0-24、172.30.88.0-24。

在各节点上分配 ping 这三个网段的网关地址，确保能通（安装完docker后）：

``` bash
$ ping 172.30.60.1
$ ping 172.30.43.2
$ ping 172.30.88.3
$
```
