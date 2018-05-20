<!-- toc -->

tags: node, flanneld, docker, kubeconfig, kubelet, kube-proxy

# 部署 Node 节点

kubernetes Node 节点包含如下组件：

+ flanneld
+ docker
+ kubelet
+ kube-proxy

## 使用的变量

本文档用到的变量定义如下：

``` bash
$ # 替换为 kubernetes master 集群任一机器 IP
$ export MASTER_IP="192.168.0.130"
$ export KUBE_APISERVER="https://192.168.0.130:6443"
$ # 当前部署的节点 IP
$ export NODE_IP="192.168.0.131"
$ # 导入用到的其它全局变量：ETCD_ENDPOINTS、FLANNEL_ETCD_PREFIX、CLUSTER_CIDR、CLUSTER_DNS_SVC_IP、CLUSTER_DNS_DOMAIN、SERVICE_CIDR
$ source /etc/environment
$
```

## 安装和配置 flanneld

参考 [05-部署Flannel网络.md](./05-部署Flannel网络.md)

## 安装和配置 docker

### 下载最新的 docker 二进制文件

``` bash
$ wget https://get.docker.com/builds/Linux/x86_64/docker-17.04.0-ce.tgz
$ tar -xvf docker-17.04.0-ce.tgz
$ cp docker/docker* /root/local/bin
$ cp docker/completion/bash/docker /etc/bash_completion.d/
$
```

### 创建 docker 的 systemd unit 文件

``` bash
$ cat > docker.service<<EOF
[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.io

[Service]
Environment="PATH=/root/local/bin:/bin:/sbin:/usr/bin:/usr/sbin"
EnvironmentFile=-/run/flannel/docker
ExecStart=/root/local/bin/dockerd --log-level=error $DOCKER_NETWORK_OPTIONS
ExecReload=/bin/kill -s HUP $MAINPID
Restart=on-failure
RestartSec=5
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
Delegate=yes
KillMode=process

[Install]
WantedBy=multi-user.target
EOF
```

+ dockerd 运行时会调用其它 docker 命令，如 docker-proxy，所以需要将 docker 命令所在的目录加到 PATH 环境变量中；
+ flanneld 启动时将网络配置写入到 `/run/flannel/docker` 文件中的变量 `DOCKER_NETWORK_OPTIONS`，dockerd 命令行上指定该变量值来设置 docker0 网桥参数；
+ 如果指定了多个 `EnvironmentFile` 选项，则必须将 `/run/flannel/docker` 放在最后(确保 docker0 使用 flanneld 生成的 bip 参数)；
+ 不能关闭默认开启的 `--iptables` 和 `--ip-masq` 选项；
+ 如果内核版本比较新，建议使用 `overlay` 存储驱动；
+ docker 从 1.13 版本开始，可能将 **iptables FORWARD chain的默认策略设置为DROP**，从而导致 ping 其它 Node 上的 Pod IP 失败，遇到这种情况时，需要手动设置策略为 `ACCEPT`：

  ``` bash
  $ sudo iptables -P FORWARD ACCEPT
  $
  ```
  并且把以下命令写入/etc/rc.local文件中，防止节点重启**iptables FORWARD chain的默认策略又还原为DROP**
  
  ``` bash
  sleep 60 && /sbin/iptables -P FORWARD ACCEPT
  ```


+ 为了加快 pull image 的速度，可以使用国内的仓库镜像服务器，同时增加下载的并发数。(如果 dockerd 已经运行，则需要重启 dockerd 生效。)

    ``` bash
    $ cat /etc/docker/daemon.json
    {
      "registry-mirrors": ["https://docker.mirrors.ustc.edu.cn", "hub-mirror.c.163.com"],
      "max-concurrent-downloads": 10
    }
    ```

完整 unit 见 [docker.service](https://github.com/opsnull/follow-me-install-kubernetes-cluster/blob/master/systemd/docker.service)

### 启动 dockerd

``` bash
$ sudo cp docker.service /etc/systemd/system/docker.service
$ sudo systemctl daemon-reload
$ sudo systemctl stop firewalld
$ sudo systemctl disable firewalld
$ sudo iptables -F && sudo iptables -X && sudo iptables -F -t nat && sudo iptables -X -t nat
$ sudo systemctl enable docker
$ sudo systemctl start docker
$
```

+ 需要关闭 firewalld(centos7)/ufw(ubuntu16.04)，否则可能会重复创建的 iptables 规则；
+ 最好清理旧的 iptables rules 和 chains 规则；

### 检查 docker 服务

``` bash
$ docker version
$
```

## 安装和配置 kubelet

kubelet 启动时向 kube-apiserver 发送 TLS bootstrapping 请求，需要先将 bootstrap token 文件中的 kubelet-bootstrap 用户赋予 system:node-bootstrapper 角色，然后 kubelet 才有权限创建认证请求(certificatesigningrequests)：

``` bash
$ kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper --user=kubelet-bootstrap
$
```

+ `--user=kubelet-bootstrap` 是文件 `/etc/kubernetes/token.csv` 中指定的用户名，同时也写入了文件 `/etc/kubernetes/bootstrap.kubeconfig`；

### 下载最新的 kubelet 和 kube-proxy 二进制文件

``` bash
$ wget https://dl.k8s.io/v1.6.2/kubernetes-server-linux-amd64.tar.gz
$ tar -xzvf kubernetes-server-linux-amd64.tar.gz
$ cd kubernetes
$ tar -xzvf  kubernetes-src.tar.gz
$ sudo cp -r ./server/bin/{kube-proxy,kubelet} /root/local/bin/
$
```

## 创建 kubelet bootstrapping kubeconfig 文件(每个kubelet节点都执行)

``` bash
$ # 设置集群参数
$ kubectl config set-cluster kubernetes \
  --certificate-authority=/etc/kubernetes/ssl/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=bootstrap.kubeconfig
$ # 设置客户端认证参数
$ kubectl config set-credentials kubelet-bootstrap \
  --token=${BOOTSTRAP_TOKEN} \
  --kubeconfig=bootstrap.kubeconfig
$ # 设置上下文参数
$ kubectl config set-context default \
  --cluster=kubernetes \
  --user=kubelet-bootstrap \
  --kubeconfig=bootstrap.kubeconfig
$ # 设置默认上下文
$ kubectl config use-context default --kubeconfig=bootstrap.kubeconfig
$ mv bootstrap.kubeconfig /etc/kubernetes/
```

+ `--embed-certs` 为 `true` 时表示将 `certificate-authority` 证书写入到生成的 `bootstrap.kubeconfig` 文件中；
+ 设置 kubelet 客户端认证参数时**没有**指定秘钥和证书，后续由 `kube-apiserver` 自动生成；

### 创建 kubelet 的 systemd unit 文件

``` bash
$ sudo mkdir /var/lib/kubelet # 必须先创建工作目录
$ cat > kubelet.service <<EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=/var/lib/kubelet
ExecStart=/root/local/bin/kubelet \\
  --address=${NODE_IP} \\
  --hostname-override=${NODE_IP} \\
  --pod-infra-container-image=registry.access.redhat.com/rhel7/pod-infrastructure:latest \\
  --experimental-bootstrap-kubeconfig=/etc/kubernetes/bootstrap.kubeconfig \\
  --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \\
  --require-kubeconfig \\
  --cert-dir=/etc/kubernetes/ssl \\
  --cluster-dns=${CLUSTER_DNS_SVC_IP} \\
  --cluster-domain=${CLUSTER_DNS_DOMAIN} \\
  --hairpin-mode promiscuous-bridge \\
  --allow-privileged=true \\
  --serialize-image-pulls=false \\
  --logtostderr=true \\
  --v=2
ExecStartPost=/sbin/iptables -A INPUT -s 10.0.0.0/8 -p tcp --dport 4194 -j ACCEPT
ExecStartPost=/sbin/iptables -A INPUT -s 172.16.0.0/12 -p tcp --dport 4194 -j ACCEPT
ExecStartPost=/sbin/iptables -A INPUT -s 192.168.0.0/16 -p tcp --dport 4194 -j ACCEPT
ExecStartPost=/sbin/iptables -A INPUT -p tcp --dport 4194 -j DROP
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

+ `--address` 不能设置为 `127.0.0.1`，否则后续 Pods 访问 kubelet 的 API 接口时会失败，因为 Pods 访问的 `127.0.0.1` 指向自己而不是 kubelet；
+ 如果设置了 `--hostname-override` 选项，则 `kube-proxy` 也需要设置该选项，否则会出现找不到 Node 的情况；
+ `--experimental-bootstrap-kubeconfig` 指向 bootstrap kubeconfig 文件，kubelet 使用该文件中的用户名和 token 向 kube-apiserver 发送 TLS Bootstrapping 请求；
+ 管理员通过了 CSR 请求后，kubelet 自动在 `--cert-dir` 目录创建证书和私钥文件(`kubelet-client.crt` 和 `kubelet-client.key`)，然后写入 `--kubeconfig` 文件(自动创建 `--kubeconfig` 指定的文件)；
+ 建议在 `--kubeconfig` 配置文件中指定 `kube-apiserver` 地址，如果未指定 `--api-servers` 选项，则必须指定 `--require-kubeconfig` 选项后才从配置文件中读取 kue-apiserver 的地址，否则 kubelet 启动后将找不到 kube-apiserver (日志中提示未找到 API Server），`kubectl get nodes` 不会返回对应的 Node 信息;
+ `--cluster-dns` 指定 kubedns 的 Service IP(可以先分配，后续创建 kubedns 服务时指定该 IP)，`--cluster-domain` 指定域名后缀，这两个参数同时指定后才会生效；
+ kubelet cAdvisor 默认在**所有接口**监听 4194 端口的请求，对于有外网的机器来说不安全，`ExecStartPost` 选项指定的 iptables 规则只允许内网机器访问 4194 端口；

完整 unit 见 [kubelet.service](https://github.com/opsnull/follow-me-install-kubernetes-cluster/blob/master/systemd/kubelet.service)

### 启动 kubelet

``` bash
$ sudo cp kubelet.service /etc/systemd/system/kubelet.service
$ sudo systemctl daemon-reload
$ sudo systemctl enable kubelet
$ sudo systemctl start kubelet
$ systemctl status kubelet
$
```

### master节点通过 kubelet 的 TLS 证书请求

kubelet 首次启动时向 kube-apiserver 发送证书签名请求，必须通过后 kubernetes 系统才会将该 Node 加入到集群。

查看未授权的 CSR 请求：

``` bash
$ kubectl get csr
NAME        AGE       REQUESTOR           CONDITION
csr-2b308   4m        kubelet-bootstrap   Pending
$ kubectl get nodes
No resources found.
```

通过 CSR 请求：

``` bash
$ kubectl certificate approve csr-2b308
certificatesigningrequest "csr-2b308" approved
$ kubectl get nodes
NAME        STATUS    AGE       VERSION
10.64.3.7   Ready     49m       v1.6.2
```

自动生成了 kubelet kubeconfig 文件和公私钥：

``` bash
$ ls -l /etc/kubernetes/kubelet.kubeconfig
-rw------- 1 root root 2284 Apr  7 02:07 /etc/kubernetes/kubelet.kubeconfig
$ ls -l /etc/kubernetes/ssl/kubelet*
-rw-r--r-- 1 root root 1046 Apr  7 02:07 /etc/kubernetes/ssl/kubelet-client.crt
-rw------- 1 root root  227 Apr  7 02:04 /etc/kubernetes/ssl/kubelet-client.key
-rw-r--r-- 1 root root 1103 Apr  7 02:07 /etc/kubernetes/ssl/kubelet.crt
-rw------- 1 root root 1675 Apr  7 02:07 /etc/kubernetes/ssl/kubelet.key
```

## 配置 kube-proxy

### 创建 kube-proxy 证书

创建 kube-proxy 证书签名请求：

``` bash
$ cat kube-proxy-csr.json
{
  "CN": "system:kube-proxy",
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
```

+ CN 指定该证书的 User 为 `system:kube-proxy`；
+ `kube-apiserver` 预定义的 RoleBinding `system:node-proxier` 将User `system:kube-proxy` 与 Role `system:node-proxier` 绑定，该 Role 授予了调用 `kube-apiserver` Proxy 相关 API 的权限；
+ hosts 属性值为空列表；

生成 kube-proxy 客户端证书和私钥：

``` bash
$ cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
  -ca-key=/etc/kubernetes/ssl/ca-key.pem \
  -config=/etc/kubernetes/ssl/ca-config.json \
  -profile=kubernetes  kube-proxy-csr.json | cfssljson -bare kube-proxy
$ ls kube-proxy*
kube-proxy.csr  kube-proxy-csr.json  kube-proxy-key.pem  kube-proxy.pem
$ sudo mv kube-proxy*.pem /etc/kubernetes/ssl/
$ rm kube-proxy.csr  kube-proxy-csr.json
$
```

### 创建 kube-proxy kubeconfig 文件

``` bash
$ # 设置集群参数
$ kubectl config set-cluster kubernetes \
  --certificate-authority=/etc/kubernetes/ssl/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=kube-proxy.kubeconfig
$ # 设置客户端认证参数
$ kubectl config set-credentials kube-proxy \
  --client-certificate=/etc/kubernetes/ssl/kube-proxy.pem \
  --client-key=/etc/kubernetes/ssl/kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig
$ # 设置上下文参数
$ kubectl config set-context default \
  --cluster=kubernetes \
  --user=kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig
$ # 设置默认上下文
$ kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
$ mv kube-proxy.kubeconfig /etc/kubernetes/
```

+ 设置集群参数和客户端认证参数时 `--embed-certs` 都为 `true`，这会将 `certificate-authority`、`client-certificate` 和 `client-key` 指向的证书文件内容写入到生成的 `kube-proxy.kubeconfig` 文件中；
+ `kube-proxy.pem` 证书中 CN 为 `system:kube-proxy`，`kube-apiserver` 预定义的 RoleBinding `cluster-admin` 将User `system:kube-proxy` 与 Role `system:node-proxier` 绑定，该 Role 授予了调用 `kube-apiserver` Proxy 相关 API 的权限；

### 创建 kube-proxy 的 systemd unit 文件

``` bash
$ sudo mkdir -p /var/lib/kube-proxy # 必须先创建工作目录
$ cat > kube-proxy.service <<EOF
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
WorkingDirectory=/var/lib/kube-proxy
ExecStart=/root/local/bin/kube-proxy \\
  --bind-address=${NODE_IP} \\
  --hostname-override=${NODE_IP} \\
  --cluster-cidr=${CLUSTER_CIDR} \\
  --kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig \\
  --logtostderr=true \\
  --v=2
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
```

+ `--hostname-override` 参数值必须与 kubelet 的值一致，否则 kube-proxy 启动后会找不到该 Node，从而不会创建任何 iptables 规则；
+ `--cluster-cidr` 必须与 kube-controller-manager 的 `--cluster-cidr` 选项值一致；
+ kube-proxy 根据 `--cluster-cidr` 判断集群内部和外部流量，指定 `--cluster-cidr` 或 `--masquerade-all` 选项后 kube-proxy 才会对访问 Service IP 的请求做 SNAT；
+ `--kubeconfig` 指定的配置文件嵌入了 kube-apiserver 的地址、用户名、证书、秘钥等请求和认证信息；
+ 预定义的 RoleBinding `cluster-admin` 将User `system:kube-proxy` 与 Role `system:node-proxier` 绑定，该 Role 授予了调用 `kube-apiserver` Proxy 相关 API 的权限；

完整 unit 见 [kube-proxy.service](https://github.com/opsnull/follow-me-install-kubernetes-cluster/blob/master/systemd/kube-proxy.service)

### 启动 kube-proxy

``` bash
$ sudo cp kube-proxy.service /etc/systemd/system/
$ sudo systemctl daemon-reload
$ sudo systemctl enable kube-proxy
$ sudo systemctl start kube-proxy
$ systemctl status kube-proxy
$
```

## 验证集群功能

定义文件：

``` bash
$ cat nginx-ds.yml
apiVersion: v1
kind: Service
metadata:
  name: nginx-ds
  labels:
    app: nginx-ds
spec:
  type: NodePort
  selector:
    app: nginx-ds
  ports:
  - name: http
    port: 80
    targetPort: 80

---

apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: nginx-ds
  labels:
    addonmanager.kubernetes.io/mode: Reconcile
spec:
  template:
    metadata:
      labels:
        app: nginx-ds
    spec:
      containers:
      - name: my-nginx
        image: nginx:1.7.9
        ports:
        - containerPort: 80
```

创建 Pod 和服务：

``` bash
$ kubectl create -f nginx-ds.yml
service "nginx-ds" created
daemonset "nginx-ds" created
```

### 检查节点状态

``` bash
$ kubectl get nodes
NAME        STATUS    AGE       VERSION
10.64.3.7   Ready     8d        v1.6.2
10.64.3.8   Ready     8d        v1.6.2
```

都为 Ready 时正常。

### 检查各 Node 上的 Pod IP 连通性

``` bash
$ kubectl get pods  -o wide|grep nginx-ds
nginx-ds-6ktz8              1/1       Running            0          5m        172.30.25.19   10.64.3.7
nginx-ds-6ktz9              1/1       Running            0          5m        172.30.20.20   10.64.3.8
```

可见，nginx-ds 的 Pod IP 分别是 `172.30.25.19`、`172.30.20.20`，在所有 Node 上分别 ping 这两个 IP，看是否连通。

### 检查服务 IP 和端口可达性

``` bash
$ kubectl get svc |grep nginx-ds
nginx-ds     10.254.136.178   <nodes>       80:8744/TCP         11m
```

可见：

+ 服务IP：10.254.136.178
+ 服务端口：80
+ NodePort端口：8744

在所有 Node 上执行：

``` bash
$ curl 10.254.136.178 # `kubectl get svc |grep nginx-ds` 输出中的服务 IP
$
```

预期输出 nginx 欢迎页面内容。

### 检查服务的 NodePort 可达性

在所有 Node 上执行：

``` bash
$ export NODE_IP=10.64.3.7 # 当前 Node 的 IP
$ export NODE_PORT=8744 # `kubectl get svc |grep nginx-ds` 输出中 80 端口映射的 NodePort
$ curl ${NODE_IP}:${NODE_PORT}
$
```

预期输出 nginx 欢迎页面内容。
