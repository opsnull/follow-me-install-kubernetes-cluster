<!-- toc -->

tags: master, kube-apiserver, kube-scheduler, kube-controller-manager

# 部署 master 节点

kubernetes master 节点包含的组件：

+ kube-apiserver
+ kube-scheduler
+ kube-controller-manager

目前这三个组件需要部署在同一台机器上：

+ `kube-scheduler`、`kube-controller-manager` 和 `kube-apiserver` 三者的功能紧密相关；
+ 同时只能有一个 `kube-scheduler`、`kube-controller-manager` 进程处于工作状态，如果运行多个，则需要通过选举产生一个 leader；

本文档介绍部署单机 kubernetes master 节点的步骤，**没有实现高可用 master 集群**。

计划后续再介绍部署 LB 的步骤，客户端 (kubectl、kubelet、kube-proxy) 使用 LB 的 VIP 来访问 kube-apiserver，从而实现高可用 master 集群。

master 节点与 node 节点上的 Pods 通过 Pod 网络通信，所以需要在 master 节点上部署 Flannel 网络。

## 使用的变量

本文档用到的变量定义如下：

``` bash
$ export MASTER_IP=10.64.3.1  # 替换为当前部署的 master 机器 IP
$ # 导入用到的其它全局变量：SERVICE_CIDR、CLUSTER_CIDR、NODE_PORT_RANGE、ETCD_ENDPOINTS、BOOTSTRAP_TOKEN
$ source /root/local/bin/environment.sh
$
```

## 下载最新版本的二进制文件

有两种下载方式：

1. 从 [github release 页面](https://github.com/kubernetes/kubernetes/releases) 下载发布版 tarball，解压后再执行下载脚本

    ``` shell
    $ wget https://github.com/kubernetes/kubernetes/releases/download/v1.10.2/kubernetes.tar.gz
    $ tar -xzvf kubernetes.tar.gz
    ...
    $ cd kubernetes
    $ ./cluster/get-kube-binaries.sh
    ...
    ```

1. 从 [`CHANGELOG`页面](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG.md) 下载 `client` 或 `server` tarball 文件

    `server` 的 tarball `kubernetes-server-linux-amd64.tar.gz` 已经包含了 `client`(`kubectl`) 二进制文件，所以不用单独下载`kubernetes-client-linux-amd64.tar.gz`文件；

    ``` shell
    $ wget https://dl.k8s.io/v1.10.2/kubernetes-server-linux-amd64.tar.gz
    $ tar -xzvf kubernetes-server-linux-amd64.tar.gz
    ...
    $ cd kubernetes
    $ tar -xzvf  kubernetes-src.tar.gz
    ```

将二进制文件拷贝到指定路径：

``` bash
$ sudo cp server/bin/{kube-apiserver,kube-controller-manager,kube-scheduler,kubectl,kube-proxy,kubelet} /vagrant/bin/
$
```

## 安装和配置 flanneld

参考 [05-部署Flannel网络.md](./05-部署Flannel网络.md)

## 创建 kubernetes 证书

创建 kubernetes 证书签名请求

``` bash
$ cat > kubernetes-csr.json <<EOF
{
  "CN": "kubernetes",
  "hosts": [
    "127.0.0.1",
    "${MASTER_IP}",
    "${CLUSTER_KUBERNETES_SVC_IP}",
    "kubernetes",
    "kubernetes.default",
    "kubernetes.default.svc",
    "kubernetes.default.svc.cluster",
    "kubernetes.default.svc.cluster.local"
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
      "OU": "4Paradigm"
    }
  ]
}
EOF
```

+ 如果 hosts 字段不为空则需要指定授权使用该证书的 **IP 或域名列表**，所以上面分别指定了当前部署的 master 节点主机 IP；
+ 还需要添加 kube-apiserver 注册的名为 `kubernetes` 的服务 IP (Service Cluster IP)，一般是 kube-apiserver `--service-cluster-ip-range` 选项值指定的网段的**第一个IP**，如 "10.254.0.1"；

  ``` bash
  $ kubectl get svc kubernetes
  NAME         CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
  kubernetes   10.254.0.1   <none>        443/TCP   1d
  ```

生成 kubernetes 证书和私钥

``` bash
$ sudo /vagrant/bin/cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
  -ca-key=/etc/kubernetes/ssl/ca-key.pem \
  -config=/etc/kubernetes/ssl/ca-config.json \
  -profile=kubernetes kubernetes-csr.json | /vagrant/bin/cfssljson -bare kubernetes

$ ls kubernetes*
kubernetes.csr  kubernetes-csr.json  kubernetes-key.pem  kubernetes.pem

$ sudo mkdir -p /etc/kubernetes/ssl/

$ sudo cp kubernetes*.pem /etc/kubernetes/ssl/

$ rm kubernetes.csr  kubernetes-csr.json
```

## 配置和启动 kube-apiserver

### 生成一个加密配置文件

``` bash
cat > encryption-config.yaml <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF
```

将 `encryption-config.yaml` 拷贝到 `/etc/kubernetes` 目录下：

``` bash
$ sudo cp encryption-config.yaml /etc/kubernetes
$
```
### 创建 kube-apiserver 的 systemd unit 文件

``` bash
$ cat  > kube-apiserver.service <<EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
ExecStart=/vagrant/bin/kube-apiserver \\
  --enable-admission-plugins=Initializers,NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --anonymous-auth=false \\
  --experimental-encryption-provider-config=/etc/kubernetes/encryption-config.yaml \\
  --advertise-address=${MASTER_IP} \\
  --bind-address=${MASTER_IP} \\
  --insecure-bind-address=${MASTER_IP} \\
  --authorization-mode=Node,RBAC \\
  --runtime-config=api/all \\
  --kubelet-https=true \\
  --enable-bootstrap-token-auth \\
  --service-cluster-ip-range=${SERVICE_CIDR} \\
  --service-node-port-range=${NODE_PORT_RANGE} \\
  --tls-cert-file=/etc/kubernetes/ssl/kubernetes.pem \\
  --tls-private-key-file=/etc/kubernetes/ssl/kubernetes-key.pem \\
  --client-ca-file=/etc/kubernetes/ssl/ca.pem \\
  --service-account-key-file=/etc/kubernetes/ssl/ca-key.pem \\
  --etcd-cafile=/etc/kubernetes/ssl/ca.pem \\
  --etcd-certfile=/etc/kubernetes/ssl/kubernetes.pem \\
  --etcd-keyfile=/etc/kubernetes/ssl/kubernetes-key.pem \\
  --etcd-servers=${ETCD_ENDPOINTS} \\
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
+ `--experimental-encryption-provider-config`
+ `--authorization-mode=Node,RBAC` 指定在安全端口使用 Node 和 RBAC 授权模式，拒绝未通过授权的请求；
+ kube-scheduler、kube-controller-manager 一般和 kube-apiserver 部署在同一台机器上，它们使用**非安全端口**和 kube-apiserver通信;
+ kubelet、kube-proxy、kubectl 部署在其它 Node 节点上，如果通过**安全端口**访问 kube-apiserver，则必须先通过 TLS 证书认证，再通过 RBAC 授权；
+ kube-proxy、kubectl 通过在使用的证书里指定相关的 User、Group 来达到通过 RBAC 授权的目的；
+ 如果使用了 kubelet TLS Boostrap 机制，则不能再指定 `--kubelet-certificate-authority`、`--kubelet-client-certificate` 和 `--kubelet-client-key` 选项，否则后续 kube-apiserver 校验 kubelet 证书时出现 ”x509: certificate signed by unknown authority“ 错误；
+ `--enable-admission-plugins` 值必须包含 `ServiceAccount`，否则部署集群插件时会失败；同时包含 NodeRestriction，用于限制 Node 的认证和授权；
+ `--bind-address` 不能为 `127.0.0.1`；
+ `--service-cluster-ip-range` 指定 Service Cluster IP 地址段，该地址段不能路由可达；
+ `--service-node-port-range=${NODE_PORT_RANGE}` 指定 NodePort 的端口范围；
+ `--client-ca-file` 启用 X509 认证；
+ 缺省情况下 kubernetes 对象保存在 etcd `/registry` 路径下，可以通过 `--etcd-prefix` 参数进行调整；

完整 unit 见 [kube-apiserver.service](https://github.com/opsnull/follow-me-install-kubernetes-cluster/blob/master/systemd/kube-apiserver.service)

### 启动 kube-apiserver

``` bash
$ sudo cp kube-apiserver.service /etc/systemd/system/
$ sudo systemctl daemon-reload
$ sudo systemctl enable kube-apiserver
$ sudo systemctl start kube-apiserver

$
```

### 检查 kube-apiserver 运行状态

``` bash
$ sudo systemctl status kube-apiserver

$ 打印 kube-apiserver 启动成功后写入 etcd 的信息
$ ETCDCTL_API=3 /vagrant/bin/etcdctl \
    --endpoints=https://10.64.3.1:2379 \
    --cacert=/etc/kubernetes/ssl/ca.pem \
    --cert=/etc/etcd/ssl/etcd.pem \
    --key=/etc/etcd/ssl/etcd-key.pem \
    get /registry/ --prefix --keys-only

$ kubectl version
Client Version: version.Info{Major:"1", Minor:"10", GitVersion:"v1.10.2", GitCommit:"81753b10df112992bf51bbc2c2f85208aad78335", GitTreeState:"clean", BuildDate:"2018-04-27T09:22:21Z", GoVersion:"go1.9.3", Compiler:"gc", Platform:"linux/amd64"}
Server Version: version.Info{Major:"1", Minor:"10", GitVersion:"v1.10.2", GitCommit:"81753b10df112992bf51bbc2c2f85208aad78335", GitTreeState:"clean", BuildDate:"2018-04-27T09:10:24Z", GoVersion:"go1.9.3", Compiler:"gc", Platform:"linux/amd64"}

$ kubectl get ns
NAME          STATUS    AGE
default       Active    35m
kube-public   Active    35m
kube-system   Active    35m

$ kubectl get all --all-namespaces
NAMESPACE   NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
default     service/kubernetes   ClusterIP   10.254.0.1   <none>        443/TCP   35m

$ kubectl get all
NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
service/kubernetes   ClusterIP   10.254.0.1   <none>        443/TCP   33m

$ kubectl get componentstatuses
NAME                 STATUS      MESSAGE                                                                                        ERROR
controller-manager   Unhealthy   Get http://127.0.0.1:10252/healthz: dial tcp 127.0.0.1:10252: getsockopt: connection refused
scheduler            Unhealthy   Get http://127.0.0.1:10251/healthz: dial tcp 127.0.0.1:10251: getsockopt: connection refused
etcd-1               Healthy     {"health":"true"}
etcd-0               Healthy     {"health":"true"}
etcd-2               Healthy     {"health":"true"}

```

注意：如果执行 kubectl 命令式出错，提示 `The connection to the server localhost:8080 was refused - did you specify the right host or port?`，则说明使用的 `~/.kube/config` 文件不对，请切换到正确的账户后再执行该命令；

## 配置和启动 kube-controller-manager

### 创建 kube-controller-manager 的 systemd unit 文件

``` bash
$ cat > kube-controller-manager.service <<EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/vagrant/bin/kube-controller-manager \\
  --address=127.0.0.1 \\
  --master=http://${MASTER_IP}:8080 \\
  --allocate-node-cidrs=true \\
  --service-cluster-ip-range=${SERVICE_CIDR} \\
  --cluster-cidr=${CLUSTER_CIDR} \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/etc/kubernetes/ssl/ca.pem \\
  --cluster-signing-key-file=/etc/kubernetes/ssl/ca-key.pem \\
  --service-account-private-key-file=/etc/kubernetes/ssl/ca-key.pem \\
  --root-ca-file=/etc/kubernetes/ssl/ca.pem \\
  --leader-elect=true \\
  --feature-gates=RotateKubeletServerCertificate=true \\
  --controllers=*,bootstrapsigner,tokencleaner \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

+ `--address` 值必须为 `127.0.0.1`，因为当前 kube-apiserver 期望 scheduler 和 controller-manager 在同一台机器，否则：

    ``` bash
    $ kubectl get componentstatuses
    NAME                 STATUS      MESSAGE                                                                                        ERROR
    controller-manager   Unhealthy   Get http://127.0.0.1:10252/healthz: dial tcp 127.0.0.1:10252: getsockopt: connection refused
    scheduler            Unhealthy   Get http://127.0.0.1:10251/healthz: dial tcp 127.0.0.1:10251: getsockopt: connection refused
    ```

    参考：https://github.com/kubernetes-incubator/bootkube/issues/64

+ `--master=http://{MASTER_IP}:8080`：使用非安全 8080 端口与 kube-apiserver 通信；
+ `--cluster-cidr` 指定 Cluster 中 Pod 的 CIDR 范围，该网段在各 Node 间必须路由可达(flanneld保证)；
+ `--service-cluster-ip-range` 参数指定 Cluster 中 Service 的CIDR范围，该网络在各 Node 间必须路由不可达，必须和 kube-apiserver 中的参数一致；
+ `--cluster-signing-*` 指定的证书和私钥文件用来签名为 TLS BootStrap 创建的证书和私钥；
+ `--root-ca-file` 用来对 kube-apiserver 证书进行校验，**指定该参数后，才会在Pod 容器的 ServiceAccount 中放置该 CA 证书文件**；
+ `--leader-elect=true` 部署多台机器组成的 master 集群时选举产生一处于工作状态的 `kube-controller-manager` 进程；
+ `--feature-gates=RotateKubeletServerCertificate=true` 用于开启 kublet server 证书的自动更新；
+ `--controllers=*,bootstrapsigner,tokencleaner` tokencleaner 用于自动清理过期的 bootstrap token；

完整 unit 见 [kube-controller-manager.service](https://github.com/opsnull/follow-me-install-kubernetes-cluster/blob/master/systemd/kube-controller-manager.service)

### 启动 kube-controller-manager

``` bash
$ sudo cp kube-controller-manager.service /etc/systemd/system/
$ sudo systemctl daemon-reload
$ sudo systemctl enable kube-controller-manager
$ sudo systemctl start kube-controller-manager
$
```

### 检查 kube-controller-manager 的运行状态

``` bash
$ sudo systemctl status kube-controller-manager

$ kubectl get componentstatuses|grep controller-manager
controller-manager   Healthy     ok
```

## 配置和启动 kube-scheduler

### 创建 kube-scheduler 的 systemd unit 文件

``` bash
$ cat > kube-scheduler.service <<EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/vagrant/bin/kube-scheduler \\
  --address=127.0.0.1 \\
  --master=http://${MASTER_IP}:8080 \\
  --leader-elect=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

+ `--address` 值必须为 `127.0.0.1`，因为当前 kube-apiserver 期望 scheduler 和 controller-manager 在同一台机器；
+ `--master=http://{MASTER_IP}:8080`：使用非安全 8080 端口与 kube-apiserver 通信；
+ `--leader-elect=true` 部署多台机器组成的 master 集群时选举产生一处于工作状态的 `kube-controller-manager` 进程；

完整 unit 见 [kube-scheduler.service](https://github.com/opsnull/follow-me-install-kubernetes-cluster/blob/master/systemd/kube-scheduler.service)。

### 启动 kube-scheduler

``` bash
$ sudo cp kube-scheduler.service /etc/systemd/system/
$ sudo systemctl daemon-reload
$ sudo systemctl enable kube-scheduler
$ sudo systemctl start kube-scheduler
$
```

### 检查 kube-scheduler 的运行状态

``` bash
$ sudo systemctl status kube-scheduler

$ kubectl get componentstatuses|grep scheduler
scheduler            Healthy   ok
```