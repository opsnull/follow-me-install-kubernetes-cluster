<!-- toc -->

tags: etcd

# 部署高可用 etcd 集群

kuberntes 系统使用 etcd 存储所有数据，本文档介绍部署一个三节点高可用 etcd 集群的步骤，这三个节点复用 kubernetes master 机器，分别命名为`etcd-host0`、`etcd-host1`、`etcd-host2`：

+ etcd-host0：10.64.3.7
+ etcd-host1：10.64.3.8
+ etcd-host2：10.66.3.86

## 使用的变量

本文档用到的变量定义如下：

``` bash
$ export NODE_NAME=etcd-host0 # 当前部署的机器名称(随便定义，只要能区分不同机器即可)
$ export NODE_IP=10.64.3.7 # 当前部署的机器 IP
$ export NODE_IPS="10.64.3.7 10.64.3.8 10.66.3.86" # etcd 集群所有机器 IP
$ # etcd 集群各机器名称和对应的IP、端口
$ export ETCD_NODES=etcd-host0=https://10.64.3.7:2380,etcd-host1=https://10.64.3.8:2380,etcd-host2=https://10.66.3.86:2380
$
```

## TLS 认证文件

需要为 etcd 集群创建加密通信的 TLS 证书，这里复用以前创建的 kubernetes 证书：

``` bash
$ sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/kubernetes/ssl
$
```

+ kubernetes 证书的 `hosts` 字段列表中包含上面三台机器的 IP，否则后续证书校验会失败；

## 下载二进制文件

到 `https://github.com/coreos/etcd/releases` 页面下载最新版本的二进制文件：

``` bash
$ wget https://github.com/coreos/etcd/releases/download/v3.1.6/etcd-v3.1.5-linux-amd64.tar.gz
$ tar -xvf etcd-v3.1.6-linux-amd64.tar.gz
$ sudo mv etcd-v3.1.6-linux-amd64/etcd* /root/local/bin
$
```

## 创建 etcd 的 systemd unit 文件

``` bash
$ sudo mkdir -p /var/lib/etcd  # 必须先创建工作目录
$ cat > etcd.service <<EOF
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target
Documentation=https://github.com/coreos

[Service]
Type=notify
WorkingDirectory=/var/lib/etcd/
ExecStart=/root/local/bin/etcd \\
  --name=${NODE_NAME} \\
  --cert-file=/etc/kubernetes/ssl/kubernetes.pem \\
  --key-file=/etc/kubernetes/ssl/kubernetes-key.pem \\
  --peer-cert-file=/etc/kubernetes/ssl/kubernetes.pem \\
  --peer-key-file=/etc/kubernetes/ssl/kubernetes-key.pem \\
  --trusted-ca-file=/etc/kubernetes/ssl/ca.pem \\
  --peer-trusted-ca-file=/etc/kubernetes/ssl/ca.pem \\
  --initial-advertise-peer-urls=https://${NODE_IP}:2380 \\
  --listen-peer-urls=https://${NODE_IP}:2380 \\
  --listen-client-urls=https://${NODE_IP}:2379,http://127.0.0.1:2379 \\
  --advertise-client-urls=https://${NODE_IP}:2379 \\
  --initial-cluster-token=etcd-cluster-0 \\
  --initial-cluster=${ETCD_NODES} \\
  --initial-cluster-state=new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
```

+ 指定 `etcd` 的工作目录和数据目录为 `/var/lib/etcd`，需在启动服务前创建这个目录；
+ 为了保证通信安全，需要指定 etcd 的公私钥(cert-file和key-file)、Peers 通信的公私钥和 CA 证书(peer-cert-file、peer-key-file、peer-trusted-ca-file)、客户端的CA证书（trusted-ca-file）；
+ 创建 `kubernetes.pem` 证书时使用的 `kubernetes-csr.json` 文件的 `hosts` 字段**包含所有 etcd 节点的 NODE_IP**，否则证书校验会出错；
+ `--initial-cluster-state` 值为 `new` 时，`--name` 的参数值必须位于 `--initial-cluster` 列表中；

完整 unit 文件见：[etcd.service](https://github.com/opsnull/follow-me-install-kubernetes-cluster/blob/master/systemd/etcd.service)

## 启动 etcd 服务

``` bash
$ sudo mv etcd.service /etc/systemd/system/
$ sudo systemctl daemon-reload
$ sudo systemctl enable etcd
$ sudo systemctl start etcd
$ systemctl status etcd
$
```

在所有的 kubernetes master 节点重复上面的步骤，直到所有机器的 etcd 服务都已启动。

## 验证服务

在任一 etcd 集群机器上执行如下命令：

``` bash
$ for ip in ${NODE_IPS}; do
  ETCDCTL_API=3 /root/local/bin/etcdctl \
  --endpoints=https://${ip}:2379  \
  --cacert=/etc/kubernetes/ssl/ca.pem \
  --cert=/etc/kubernetes/ssl/kubernetes.pem \
  --key=/etc/kubernetes/ssl/kubernetes-key.pem \
  endpoint health; done
```

预期结果：

``` text
2017-04-10 14:50:50.011317 I | warning: ignoring ServerName for user-provided CA for backwards compatibility is deprecated
https://10.64.3.7:2379 is healthy: successfully committed proposal: took = 1.687897ms
2017-04-10 14:50:50.061577 I | warning: ignoring ServerName for user-provided CA for backwards compatibility is deprecated
https://10.64.3.8:2379 is healthy: successfully committed proposal: took = 1.246915ms
2017-04-10 14:50:50.104718 I | warning: ignoring ServerName for user-provided CA for backwards compatibility is deprecated
https://10.66.3.86:2379 is healthy: successfully committed proposal: took = 1.509229ms
```

三台 etcd 的输出均为 healthy 时表示集群服务正常（忽略 warning 信息）。