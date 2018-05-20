<!-- toc -->

tags: etcd

# 部署高可用 etcd 集群

kuberntes 系统使用 etcd 存储所有数据，本文档介绍部署一个三节点高可用 etcd 集群的步骤，这三个节点复用 kubernetes master 机器，分别命名为`etcd-host0`、`etcd-host1`、`etcd-host2`：

+ etcd-host0：10.64.3.7 >192.168.0.130
+ etcd-host1：10.64.3.8 >192.168.0.131
+ etcd-host2：10.66.3.86 >192.168.0.132

## 使用的变量

本文档用到的变量定义如下：

``` bash
$ export NODE_NAME=etcd-host0 # 当前部署的机器名称(随便定义，只要能区分不同机器即可)
$ export NODE_IP=10.64.3.7 # 当前部署的机器 IP
$ export NODE_IPS="10.64.3.7 10.64.3.8 10.66.3.86" # etcd 集群所有机器 IP
$ # etcd 集群间通信的IP和端口
$ export ETCD_NODES=etcd-host0=https://10.64.3.7:2380,etcd-host1=https://10.64.3.8:2380,etcd-host2=https://10.66.3.86:2380
$ # 导入用到的其它全局变量：ETCD_ENDPOINTS、FLANNEL_ETCD_PREFIX、CLUSTER_CIDR
$ source /root/local/bin/environment.sh
$
```

## 下载二进制文件

到 `https://github.com/coreos/etcd/releases` 页面下载最新版本的二进制文件：

``` bash
$ wget https://github.com/coreos/etcd/releases/download/v3.1.6/etcd-v3.1.6-linux-amd64.tar.gz
$ tar -xvf etcd-v3.1.6-linux-amd64.tar.gz
$ sudo mv etcd-v3.1.6-linux-amd64/etcd* /root/local/bin
$
```

## 创建 TLS 秘钥和证书

为了保证通信安全，客户端(如 etcdctl) 与 etcd 集群、etcd 集群之间的通信需要使用 TLS 加密，本节创建 etcd TLS 加密所需的证书和私钥。

创建 etcd 证书签名请求：

``` bash
$ cat > etcd-csr.json <<EOF
{
  "CN": "etcd",
  "hosts": [
    "127.0.0.1",
    "${NODE_IP}"
  ],
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

+ hosts 字段指定授权使用该证书的 etcd 节点 IP；

生成 etcd 证书和私钥：

``` bash
$ cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
  -ca-key=/etc/kubernetes/ssl/ca-key.pem \
  -config=/etc/kubernetes/ssl/ca-config.json \
  -profile=kubernetes etcd-csr.json | cfssljson -bare etcd
$ ls etcd*
etcd.csr  etcd-csr.json  etcd-key.pem etcd.pem
$ sudo mkdir -p /etc/etcd/ssl
$ sudo mv etcd*.pem /etc/etcd/ssl
$ rm etcd.csr  etcd-csr.json
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
  --cert-file=/etc/etcd/ssl/etcd.pem \\
  --key-file=/etc/etcd/ssl/etcd-key.pem \\
  --peer-cert-file=/etc/etcd/ssl/etcd.pem \\
  --peer-key-file=/etc/etcd/ssl/etcd-key.pem \\
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

最先启动的 etcd 进程会卡住一段时间，等待其它节点上的 etcd 进程加入集群，为正常现象。

在所有的 etcd 节点重复上面的步骤，直到所有机器的 etcd 服务都已启动。

## 验证服务

部署完 etcd 集群后，在任一 etcd 集群节点上执行如下命令：

``` bash
$ for ip in ${NODE_IPS}; do
  ETCDCTL_API=3 /root/local/bin/etcdctl \
  --endpoints=https://${ip}:2379  \
  --cacert=/etc/kubernetes/ssl/ca.pem \
  --cert=/etc/etcd/ssl/etcd.pem \
  --key=/etc/etcd/ssl/etcd-key.pem \
  endpoint health; done
  ###${ip}替换为本机ip
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

