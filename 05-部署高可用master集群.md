# 部署高可用 kubernetes master 集群

kubernetes master 节点包含的组件：

+ kube-apiserver
+ kube-scheduler
+ kube-controller-manager

目前这三个组件需要部署在同一台机器上：

+ `kube-scheduler`、`kube-controller-manager` 和 `kube-apiserver` 三者的功能紧密相关；
+ 同时只能有一个 `kube-scheduler`、`kube-controller-manager` 进程处于工作状态，如果运行多个，则需要通过选举产生一个 leader；

本文档记录部署一个三个节点的高可用 kubernetes master 集群步骤。（后续创建一个 load balancer 来代理访问 kube-apiserver 的请求）


## TLS 证书文件

``` bash
$ sudo mkdir -p /etc/kubernetes/ssl
$ sudo cp token.csv /etc/kubernetes/ssl
$ sudo cp ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem /etc/kubernetes/ssl
$
```

## 下载最新版本的二进制文件

有两种下载方式

1. 从 [github release 页面](https://github.com/kubernetes/kubernetes/releases) 下载发布版 tarball，解压后再执行下载脚本

    ``` shell
    $ wget https://github.com/kubernetes/kubernetes/releases/download/v1.6.1/kubernetes.tar.gz
    $ tar -xzvf kubernetes.tar.gz
    ...
    $ cd kubernetes
    $ ./cluster/get-kube-binaries.sh
    ...
    ```

1. 从 [`CHANGELOG`页面](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG.md) 下载 `client` 或 `server` tarball 文件

    `server` 的 tarball `kubernetes-server-linux-amd64.tar.gz` 已经包含了 `client`(`kubectl`) 二进制文件，所以不用单独下载`kubernetes-client-linux-amd64.tar.gz`文件；

    ``` shell
    $ # wget https://dl.k8s.io/v1.6.1/kubernetes-client-linux-amd64.tar.gz
    $ wget https://dl.k8s.io/v1.6.1/kubernetes-server-linux-amd64.tar.gz
    $ tar -xzvf kubernetes-server-linux-amd64.tar.gz
    ...
    $ cd kubernetes
    $ tar -xzvf  kubernetes-src.tar.gz
    ```

将二进制文件拷贝到指定路径

``` bash
$ sudo cp -r server/bin/{kube-apiserver,kube-controller-manager,kube-scheduler,kubectl,kube-proxy,kubelet} /root/local/bin/
$
```

## 配置和启动 kube-apiserver

### 创建 kube-apiserver 的 systemd unit 文件

``` bash
$ export INTERNAL_IP=10.64.3.7  # 部署时需要修改该环境变量值
$ cat  > kube-apiserver.service <<EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
ExecStart=/root/local/bin/kube-apiserver \\
  --admission-control=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --advertise-address=${INTERNAL_IP} \\
  --bind-address=${INTERNAL_IP} \\
  --insecure-bind-address=${INTERNAL_IP} \\
  --authorization-mode=RBAC \\
  --runtime-config=rbac.authorization.k8s.io/v1alpha1 \\
  --kubelet-https=true \\
  --experimental-bootstrap-token-auth \\
  --token-auth-file=/etc/kubernetes/token.csv \\
  --service-cluster-ip-range=10.254.0.0/16 \\
  --service-node-port-range=30000-32767 \\
  --tls-cert-file=/etc/kubernetes/ssl/kubernetes.pem \\
  --tls-private-key-file=/etc/kubernetes/ssl/kubernetes-key.pem \\
  --client-ca-file=/etc/kubernetes/ssl/ca.pem \\
  --service-account-key-file=/etc/kubernetes/ca-key.pem \\
  --etcd-cafile=/etc/kubernetes/ssl/ca.pem \\
  --etcd-certfile=/etc/kubernetes/ssl/kubernetes.pem \\
  --etcd-keyfile=/etc/kubernetes/ssl/kubernetes-key.pem \\
  --etcd-servers=https://10.64.3.7:2379,https://10.64.3.8:2379,https://10.66.3.86:2379 \\
  --enable-swagger-ui=true \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/lib/audit.log \\
  --event-ttl=1h \\
  --v=2
Restart=on-failure
RestartSec=5
Type=notify
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
```

+ kube-apiserver 1.6 版本开始使用 etcd v3 API 和存储格式；
+ `--authorization-mode=RBAC` 指定在安全端口使用 RBAC 授权模式，拒绝未通过授权的请求；
+ kube-scheduler、kube-controller-manager 一般和 kube-apiserver 部署在同一台机器上，它们使用**非安全端口**和 kube-apiserver通信;
+ kubelet、kube-proxy、kubectl 部署在其它 Node 节点上，如果通过**安全端口**访问 kube-apiserver，则必须先通过 TLS 证书认证，再通过 RBAC 授权；
+ kube-proxy、kubectl 通过在使用的证书里指定相关的 User、Group 来达到通过 RBAC 授权的目的；
+ 如果使用了 kubelet TLS Boostrap 机制，则不能再指定 `--kubelet-certificate-authority`、`--kubelet-client-certificate` 和 `--kubelet-client-key` 选项，否则后续 kube-apiserver 校验 kubelet 证书时出现 ”x509: certificate signed by unknown authority“ 错误；
+ `--admission-control` 值必须包含 `ServiceAccount`；
+ `--bind-address` 不能为 `127.0.0.1`；
+ `--service-cluster-ip-range` 指定 Service Cluster IP 地址段，该地址段不能路由可达；
+ 缺省情况下 kubernetes 对象保存在 etcd `/registry` 路径下，可以通过 `--etcd-prefix` 参数进行调整；

完整 unit 见 [kube-apiserver.service](./systemd/kube-apiserver.service)

### 启动 kube-apiserver

``` bash
$ sudo cp kube-apiserver.service /etc/systemd/system/
$ sudo systemctl daemon-reload
$ sudo systemctl enable kube-apiserver
$ sudo systemctl start kube-apiserver
$ sudo systemctl status kube-apiserver
$
```

## 配置和启动 kube-controller-manager

### 创建 kube-controller-manager 的 systemd unit 文件

``` bash
$ export INTERNAL_IP=10.64.3.7 # 部署时需要修改该环境变量值
$ cat > kube-controller-manager.service <<EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/usr/bin/kube-controller-manager \\
  --address=127.0.0.1 \\
  --master=http://${INTERNAL_IP}:8080 \\
  --allocate-node-cidrs=true \\
  --service-cluster-ip-range=10.254.0.0/16 \\
  --cluster-cidr=172.30.0.0/16 \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/etc/kubernetes/ssl/ca.pem \\
  --cluster-signing-key-file=/etc/kubernetes/ssl/ca-key.pem \\
  --service-account-private-key-file=/etc/kubernetes/ssl/ca-key.pem \\
  --root-ca-file=/etc/kubernetes/ssl/ca.pem \\
  --leader-elect=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

+ `--cluster-cidr` 指定 Cluster 中 Pod 的 CIDR 范围，该网段在各 Node 间必须路由可达(flanneld保证)；
+ `--service-cluster-ip-range` 参数指定 Cluster 中 Service 的CIDR范围，该网络在各 Node 间必须路由不可达，必须和 kube-apiserver 中的参数一致；
+ `--master=http://${INTERNAL_IP}:8080`：使用非安全 8080 端口与 kube-apiserver 通信；
+ `--cluster-signing-*` 指定的证书和私钥文件用来签名为 TLS BootStrap 创建的证书和私钥；
+ `--root-ca-file` 用来对 kube-apiserver 证书进行校验，**指定该参数后，才会在Pod 容器的 ServiceAccount 中放置该 CA 证书文件**；
+ `--address` 值必须为 `127.0.0.1`，因为当前 kube-apiserver 期望 scheduler 和 controller-manager 在同一台机器，否则：

    ``` bash
    $ kubectl get componentstatuses
    NAME                 STATUS      MESSAGE                                                                                        ERROR
    controller-manager   Unhealthy   Get http://127.0.0.1:10252/healthz: dial tcp 127.0.0.1:10252: getsockopt: connection refused
    scheduler            Unhealthy   Get http://127.0.0.1:10251/healthz: dial tcp 127.0.0.1:10251: getsockopt: connection refused
    ```

    参考：https://github.com/kubernetes-incubator/bootkube/issues/64

完整 unit 见 [kube-controller-manager.service](./systemd/kube-controller-manager.service)

### 启动 kube-controller-manager

``` bash
$ sudo cp kube-controller-manager.service /etc/systemd/system/
$ sudo systemctl daemon-reload
$ sudo systemctl enable kube-controller-manager
$ sudo systemctl start kube-controller-manager
$
```

## 配置和启动 kube-scheduler

### 创建 kube-controller-manager 的 systemd unit 文件

``` bash
$ export INTERNAL_IP=10.64.3.7 # 部署时需要修改该环境变量值
$ cat > kube-scheduler.service <<EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/root/local/bin/kube-scheduler \\
  --leader-elect=true \\
  --master=http://${INTERNAL_IP}:8080 \\
  --address=127.0.0.1 \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

+ `--address` 值必须为 `127.0.0.1`，因为当前 kube-apiserver 期望 scheduler 和 controller-manager 在同一台机器；
+ `--master=http://${INTERNAL_IP}:8080`：使用非安全 8080 端口与 kube-apiserver 通信；

完整 unit 见 [kube-scheduler.service](./systemd/kube-scheduler.service)

### 启动 kube-scheduler

``` bash
$ sudo cp kube-scheduler.service /etc/systemd/system/
$ sudo systemctl daemon-reload
$ sudo systemctl enable kube-scheduler
$ sudo systemctl start kube-scheduler
$
```

## 验证 master 节点功能

``` bash
$ kubectl get componentstatuses
NAME                 STATUS    MESSAGE              ERROR
controller-manager   Healthy   ok
scheduler            Healthy   ok
etcd-0               Healthy   {"health": "true"}
etcd-1               Healthy   {"health": "true"}
etcd-2               Healthy   {"health": "true"}
```