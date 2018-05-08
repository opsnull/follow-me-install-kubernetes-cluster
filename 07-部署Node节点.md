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
$ export MASTER_IP=10.64.3.1
$ export KUBE_APISERVER="https://${MASTER_IP}:6443"
$ # 当前部署的节点 IP
$ export NODE_IP=10.64.3.1
$ # 当前不熟的节点名称，须符合： [a-z0-9:-]{0,255}[a-z0-9]
$ export NODE_NAME=kube-node1
$ # 导入用到的其它全局变量：ETCD_ENDPOINTS、FLANNEL_ETCD_PREFIX、CLUSTER_CIDR、CLUSTER_DNS_SVC_IP、CLUSTER_DNS_DOMAIN、SERVICE_CIDR
$ source /vagrant/bin/environment.sh
$
```

## 安装和配置 flanneld

参考 [05-部署Flannel网络.md](./05-部署Flannel网络.md)

## 安装和配置 docker

### 下载最新的 docker 二进制文件

``` bash
$ wget https://download.docker.com/linux/static/stable/x86_64/docker-18.03.0-ce.tgz
$ wget https://download.docker.com/mac/static/stable/x86_64/docker-18.03.1-ce.tgz
$ tar -xvf docker-18.03.1-ce.tgz
$ cp docker/docker* /vagrant/bin
$ cp docker/completion/bash/docker /etc/bash_completion.d/
$
```

### 创建 docker 的 systemd unit 文件

``` bash
$ cat docker.service
[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.io

[Service]
Environment="PATH=/vagrant/bin:/bin:/sbin:/usr/bin:/usr/sbin"
EnvironmentFile=-/run/flannel/docker
ExecStart=/vagrant/bin/dockerd --log-level=error $DOCKER_NETWORK_OPTIONS
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
    $ sudo mkdir -p  /etc/docker/
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
$ docker system info

$ ip addr show flannel.1
4: flannel.1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue state UNKNOWN group default
    link/ether f2:4c:df:c1:cb:99 brd ff:ff:ff:ff:ff:ff
    inet 172.30.5.0/32 scope global flannel.1
       valid_lft forever preferred_lft forever
    inet6 fe80::f04c:dfff:fec1:cb99/64 scope link
       valid_lft forever preferred_lft forever

$ ip addr show docker0
5: docker0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default
    link/ether 02:42:67:e2:53:67 brd ff:ff:ff:ff:ff:ff
    inet 172.30.5.1/24 brd 172.30.5.255 scope global docker0
       valid_lft forever preferred_lft forever

```

## 安装和配置 kubelet

### 下载最新的 kubelet 和 kube-proxy 二进制文件

``` bash
$ wget https://dl.k8s.io/v1.10.2/kubernetes-server-linux-amd64.tar.gz
$ tar -xzvf kubernetes-server-linux-amd64.tar.gz
$ cd kubernetes
$ tar -xzvf  kubernetes-src.tar.gz
$ sudo cp -r ./server/bin/{kube-proxy,kubelet,kubeadmin} /vagrant/bin/
$
```

### 安装依赖

``` bash
$ sudo apt-get update && apt-get install conntrack ipvsadm ipset jq
$ sudo modprobe ip_vs
```

### 使用 kubeadm 创建 kubelet bootstrap token

```
$ export BOOTSTRAP_TOKEN=$(kubeadm token create \
    --description kubelet-bootstrap-token \
    --groups system:bootstrappers:${NODE_NAME} \
    --kubeconfig ~/.kube/config)
dr07qg.7xam3s96bbiy90pa

$ kubeadm token list --kubeconfig ~/.kube/config
TOKEN                     TTL       EXPIRES                USAGES                   DESCRIPTION               EXTRA GROUPS
lemy40.rlolr6vhc2bvsqjb   23h       2018-05-07T06:15:08Z   authentication,signing   kubelet-bootstrap-token   system:bootstrappers:kube-node1

$ kubeadm token list --kubeconfig ~/.kube/config
TOKEN                     TTL       EXPIRES                USAGES                   DESCRIPTION               EXTRA GROUPS
lemy40.rlolr6vhc2bvsqjb   23h       2018-05-07T06:02:17Z   authentication,signing   kubelet-bootstrap-token   system:bootstrappers:kube-node1

$ kubectl get secrets  -n kube-system
NAME                     TYPE                            DATA      AGE
bootstrap-token-lemy40   bootstrap.kubernetes.io/token   7         2m
```

+ 使用 kubeadm token create 命令为各 Node 创建 bootstrap token，注意默认创建的 token 有效期为 1 天，超期后将不能再被使用，且会被 kube-controller-manager 的 tokencleaner 清理(如果启用该 controller 的话)；
+ kube-apiserver 认证通过 kubelet 的 bootstrap token 后，设置请求的 user 为 system:bootstrap:<Token ID>，group 为 system:bootstrappers；

## 创建 kubelet bootstrapping kubeconfig 文件

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
$ sudo mv bootstrap.kubeconfig /etc/kubernetes/
```

+ `--embed-certs` 为 `true` 时表示将 `certificate-authority` 证书写入到生成的 `bootstrap.kubeconfig` 文件中；
+ 设置 kubelet 客户端认证参数时**没有**指定秘钥和证书，后续由 `kube-apiserver` 自动生成；

### 创建 kubelet 的 systemd unit 文件

从 v1.10 开始有些参数必须在 kubelet.config.json 中配置，如：

 --pod-manifest-path、 --allow-privileged、--cluster-dns、--cluster-domain、--cgroups-per-qos、--enforce-node-allocatable、--cadvisor-port、--kube-reserved-cgroup、--system-reserved-cgroup、--cgroup-root

kublet 在运行后，可以使用如下命令获取配置参数：

``` bash
$ curl -sSL http://localhost:8001/api/v1/nodes/kube-node1/proxy/configz | jq \
  '.kubeletconfig|.kind="KubeletConfiguration"|.apiVersion="kubelet.config.k8s.io/v1beta1"'
```

也可以从如下文件中获取所有配置参数：

https://github.com/kubernetes/kubernetes/blob/master/pkg/kubelet/apis/kubeletconfig/v1beta1/types.go


``` bash
$ sudo mkdir /var/lib/kubelet # 必须先创建工作目录
$ cat > kubelet.config.json <<EOF
{
  "kind": "KubeletConfiguration",
  "apiVersion": "kubelet.config.k8s.io/v1beta1",
  "authorization": {
    "mode": "AlwaysAllow",
    "webhook": {
      "cacheAuthorizedTTL": "5m0s",
      "cacheUnauthorizedTTL": "30s"
    }
  },
  "address": "${NODE_IP}",
  "readOnlyPort": 10255,
  "cgroupDriver": "cgroupfs",
  "hairpinMode": "promiscuous-bridge",
  "serializeImagePulls": false,
  "featureGates": {
    "RotateKubeletClientCertificate": true,
    "RotateKubeletServerCertificate": true
  },
  "clusterDomain": "cluster.local.",
  "clusterDNS": ["10.254.0.2"]
}
EOF

$ cat > kubelet.service <<EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=/var/lib/kubelet
ExecStart=/vagrant/bin/kubelet \\
  --config=/etc/kubernetes/kubelet.config.json \\
  --hostname-override=${NODE_NAME} \\
  --pod-infra-container-image=registry.access.redhat.com/rhel7/pod-infrastructure:latest \\
  --bootstrap-kubeconfig=/etc/kubernetes/bootstrap.kubeconfig \\
  --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \\
  --cert-dir=/etc/kubernetes/ssl \\
  --allow-privileged=true \\
  --logtostderr=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

+ `--address` 不能设置为 `127.0.0.1`，否则后续 Pods 访问 kubelet 的 API 接口时会失败，因为 Pods 访问的 `127.0.0.1` 指向自己而不是 kubelet；
+ 如果设置了 `--hostname-override` 选项，则 `kube-proxy` 也需要设置该选项，否则会出现找不到 Node 的情况；
+ `--bootstrap-kubeconfig` 指向 bootstrap kubeconfig 文件，kubelet 使用该文件中的用户名和 token 向 kube-apiserver 发送 TLS Bootstrapping 请求；
+ 自动 approve kubelet 的 csr 请求后，kubelet 自动在 `--cert-dir` 目录创建证书和私钥文件(`kubelet-client.crt` 和 `kubelet-client.key`)，然后写入 `--kubeconfig` 文件(自动创建 `--kubeconfig` 指定的文件)；
+ `--feature-gates` 启用自动更新 kublet client&server 证书的功能；
+ kubelet cAdvisor 默认在**所有接口**监听 4194 端口的请求，对于有外网的机器来说不安全，`ExecStartPost` 选项指定的 iptables 规则只允许内网机器访问 4194 端口；
+ 有些选项必须在 kubelet.config.json 文件中指定，如 clusterDomain、clusterDNS、address、readOnlyPort、featureGates、authorization 等，注意 clusterDNS 是数组形式；
+ 如果未指定 authorization 选项，则 kubelet-apiserver 访问 kubelet 时提示 Unauthorized;
+ 如果未指定 readOnlyPort 选择，则 kubelet 不会监听该端口，会导致后续 heapster 获取不到 kublet 的状态和 metric；

完整 unit 见 [kubelet.service](https://github.com/opsnull/follow-me-install-kubernetes-cluster/blob/master/systemd/kubelet.service)

### 启动 kubelet

``` bash
$ sudo cp kubelet.config.json /etc/kubernetes
$ sudo cp kubelet.service /etc/systemd/system/kubelet.service
$ sudo systemctl daemon-reload
$ sudo systemctl enable kubelet
$ sudo systemctl start kubelet
$ systemctl status kubelet
$
```

### 赋予 system:bootstrappers group 创建 CSR 的权限

kubelet 启动后，使用 bootstrap.kubeconfig 中的 token 向 kube-apiserver 发送 CSR 请求，kube-apiserver 收到请求后，查找以前使用 kubeadm 创建的对应 token，匹配后，认证通过，然后将请求的 user 设置为 system:bootstrap:<Token ID>，group 设置为 system:bootstrappers。

默认情况下这个 user 和 group 没有创建 CSR 的权限，查看 kubelet 的日志：

``` bash
$ sudo journalctl -u kubelet -a |grep -A 2 'certificatesigningrequests'
May 06 06:42:36 kube-node1 kubelet[26986]: F0506 06:42:36.314378   26986 server.go:233] failed to run Kubelet: cannot create certificate signing request: certificatesigningrequests.certificates.k8s.io is forbidden: User "system:bootstrap:lemy40" cannot create certificatesigningrequests.certificates.k8s.io at the cluster scope
May 06 06:42:36 kube-node1 systemd[1]: kubelet.service: Main process exited, code=exited, status=255/n/a
May 06 06:42:36 kube-node1 systemd[1]: kubelet.service: Failed with result 'exit-code'.
```

解决办法是：创建一个 clusterrolebinding，将 system:bootstrappers group 赋予 system:node-bootstrapper 的 role 权限：

``` bash
$ kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper --group=system:bootstrappers
```

### 手动 approve kubelet 的 CSR 请求

kubelet 创建了 CSR 后，需要 approve 后，kube-controller-manager 才会为它生成配置文件： kubelet.kubeconfig，client 和 server 证书&私钥文件。

启动 kubelet 后，可以看到创建的 csr 处于 pending 状态，没有生成 node 对象：

``` bash
$ kubectl get csr
NAME                                                   AGE       REQUESTOR                 CONDITION
node-csr-TencGqfnI4ItnqnTF01bSe2OIUTO0T8G1jNWCWoRezU   8s        system:bootstrap:lemy40   Pending

$ kubectl get nodes
No resources found.
```

可以使用 `kubectl certificate approve XXX` 命令来**手动** approve CSR XXX，但从 kubernetes v1.8 开始，支持**自动** approve csr 了，而且支持自动更新证书！

### 自动 approve kublet 的 CSR 请求

创建三个 ClusterRoleBinding，用于自动 approve client、renewclient、renewserver 的证书：

``` bash
$ cat csr-crb.yaml
 # Approve all CSRs for the group "system:bootstrappers"
 kind: ClusterRoleBinding
 apiVersion: rbac.authorization.k8s.io/v1
 metadata:
   name: auto-approve-csrs-for-group
 subjects:
 - kind: Group
   name: system:bootstrappers
   apiGroup: rbac.authorization.k8s.io
 roleRef:
   kind: ClusterRole
   name: system:certificates.k8s.io:certificatesigningrequests:nodeclient
   apiGroup: rbac.authorization.k8s.io
---
 # To let a node of the group "system:bootstrappers" renew its own credentials
 kind: ClusterRoleBinding
 apiVersion: rbac.authorization.k8s.io/v1
 metadata:
   name: node-client-cert-renewal
 subjects:
 - kind: Group
   name: system:bootstrappers
   apiGroup: rbac.authorization.k8s.io
 roleRef:
   kind: ClusterRole
   name: system:certificates.k8s.io:certificatesigningrequests:selfnodeclient
   apiGroup: rbac.authorization.k8s.io
---
# A ClusterRole which instructs the CSR approver to approve a node requesting a
# serving cert matching its client cert.
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: approve-node-server-renewal-csr
rules:
- apiGroups: ["certificates.k8s.io"]
  resources: ["certificatesigningrequests/selfnodeserver"]
  verbs: ["create"]
---
 # To let a node of the group "system:nodes" renew its own server credentials
 kind: ClusterRoleBinding
 apiVersion: rbac.authorization.k8s.io/v1
 metadata:
   name: node-server-cert-renewal
 subjects:
 - kind: Group
   name: system:nodes
   apiGroup: rbac.authorization.k8s.io
 roleRef:
   kind: ClusterRole
   name: approve-node-server-renewal-csr
   apiGroup: rbac.authorization.k8s.io

$ kubectl apply -f csr-crb.yaml
clusterrolebinding.rbac.authorization.k8s.io "auto-approve-csrs-for-group" created
clusterrolebinding.rbac.authorization.k8s.io "node-client-cert-renewal" created
clusterrole.rbac.authorization.k8s.io "approve-node-server-renewal-csr" created
clusterrolebinding.rbac.authorization.k8s.io "node-server-cert-renewal" created
```

过一段时间后，可以看到 K8S 自动 approve 了 node 的两个 CSR，node-csr-XXX 用于请求前面 kubelet-client*.pem 证书，csr-cksj5 用于签名 kubelet-server*.pem 证书：

``` bash
$ kubectl get csr
NAME                                                   AGE       REQUESTOR                 CONDITION
csr-7hf8v                                              30s       system:node:kube-node1    Approved,Issued
node-csr-mLFj7MBES6VTsMHA7y4WBxVSqJFXPRTvpZEZ8uSoW0s   31s       system:bootstrap:lemy40   Approved,Issued

$ kubectl get nodes
NAME         STATUS    ROLES     AGE       VERSION
kube-node1   Ready     <none>    21s       v1.10.2
```

自动生成了 kubelet kubeconfig 文件和公私钥：

``` bash
$ ls -l /etc/kubernetes/kubelet.kubeconfig
-rw------- 1 root root 2276 May  6 09:58 /etc/kubernetes/kubelet.kubeconfig

$ ls -l /etc/kubernetes/ssl/kubelet-*
-rw-r--r-- 1 root root 1042 May  6 09:58 /etc/kubernetes/ssl/kubelet-client.crt
-rw------- 1 root root  227 May  6 09:58 /etc/kubernetes/ssl/kubelet-client.key
-rw------- 1 root root 1330 May  6 09:58 /etc/kubernetes/ssl/kubelet-server-2018-05-06-09-58-50.pem
lrwxrwxrwx 1 root root   58 May  6 09:58 /etc/kubernetes/ssl/kubelet-server-current.pem -> /etc/kubernetes/ssl/kubelet-server-2018-05-06-09-58-50.pem
```

## 获取 kublet 的配置

``` bash
$ curl -sSL http://localhost:8001/api/v1/nodes/kube-node1/proxy/configz | jq \
  '.kubeletconfig|.kind="KubeletConfiguration"|.apiVersion="kubelet.config.k8s.io/v1beta1"'
{
  "syncFrequency": "1m0s",
  "fileCheckFrequency": "20s",
  "httpCheckFrequency": "20s",
  "address": "10.64.3.1",
  "port": 10250,
  "readOnlyPort": 10255,
  "authentication": {
    "x509": {},
    "webhook": {
      "enabled": false,
      "cacheTTL": "2m0s"
    },
    "anonymous": {
      "enabled": true
    }
  },
  "authorization": {
    "mode": "AlwaysAllow",
    "webhook": {
      "cacheAuthorizedTTL": "5m0s",
      "cacheUnauthorizedTTL": "30s"
    }
  },
  "registryPullQPS": 5,
  "registryBurst": 10,
  "eventRecordQPS": 5,
  "eventBurst": 10,
  "enableDebuggingHandlers": true,
  "healthzPort": 10248,
  "healthzBindAddress": "127.0.0.1",
  "oomScoreAdj": -999,
  "streamingConnectionIdleTimeout": "4h0m0s",
  "nodeStatusUpdateFrequency": "10s",
  "imageMinimumGCAge": "2m0s",
  "imageGCHighThresholdPercent": 85,
  "imageGCLowThresholdPercent": 80,
  "volumeStatsAggPeriod": "1m0s",
  "cgroupsPerQOS": true,
  "cgroupDriver": "cgroupfs",
  "cpuManagerPolicy": "none",
  "cpuManagerReconcilePeriod": "10s",
  "runtimeRequestTimeout": "2m0s",
  "hairpinMode": "promiscuous-bridge",
  "maxPods": 110,
  "podPidsLimit": -1,
  "resolvConf": "/etc/resolv.conf",
  "cpuCFSQuota": true,
  "maxOpenFiles": 1000000,
  "contentType": "application/vnd.kubernetes.protobuf",
  "kubeAPIQPS": 5,
  "kubeAPIBurst": 10,
  "serializeImagePulls": true,
  "evictionHard": {
    "imagefs.available": "15%",
    "memory.available": "100Mi",
    "nodefs.available": "10%",
    "nodefs.inodesFree": "5%"
  },
  "evictionPressureTransitionPeriod": "5m0s",
  "enableControllerAttachDetach": true,
  "makeIPTablesUtilChains": true,
  "iptablesMasqueradeBit": 14,
  "iptablesDropBit": 15,
  "featureGates": {
    "RotateKubeletClientCertificate": true,
    "RotateKubeletServerCertificate": true
  },
  "failSwapOn": true,
  "containerLogMaxSize": "10Mi",
  "containerLogMaxFiles": 5,
  "enforceNodeAllocatable": [
    "pods"
  ],
  "kind": "KubeletConfiguration",
  "apiVersion": "kubelet.config.k8s.io/v1beta1"
}
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
      "OU": "4Paradigm"
    }
  ]
}
```

+ CN 指定该证书的 User 为 `system:kube-proxy`；
+ `kube-apiserver` 预定义的 RoleBinding `system:node-proxier` 将User `system:kube-proxy` 与 Role `system:node-proxier` 绑定，该 Role 授予了调用 `kube-apiserver` Proxy 相关 API 的权限；
+ hosts 属性值为空列表；

生成 kube-proxy 客户端证书和私钥：

``` bash
$ sudo /vagrant/bin/cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
  -ca-key=/etc/kubernetes/ssl/ca-key.pem \
  -config=/etc/kubernetes/ssl/ca-config.json \
  -profile=kubernetes  kube-proxy-csr.json | /vagrant/bin/cfssljson -bare kube-proxy
$ ls kube-proxy*
kube-proxy.csr  kube-proxy-csr.json  kube-proxy-key.pem  kube-proxy.pem
$ sudo cp kube-proxy*.pem /etc/kubernetes/ssl/
$ rm kube-proxy.csr  kube-proxy-csr.json
$
```

### 创建 kube-proxy kubeconfig 文件

``` bash
$ # 设置集群参数
$ sudo /vagrant/bin/kubectl config set-cluster kubernetes \
  --certificate-authority=/etc/kubernetes/ssl/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=kube-proxy.kubeconfig

$ # 设置客户端认证参数
$ sudo /vagrant/bin/kubectl config set-credentials kube-proxy \
  --client-certificate=/etc/kubernetes/ssl/kube-proxy.pem \
  --client-key=/etc/kubernetes/ssl/kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig

$ # 设置上下文参数
$ sudo /vagrant/bin/kubectl config set-context default \
  --cluster=kubernetes \
  --user=kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig

$ # 设置默认上下文
$ sudo /vagrant/bin/kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
$ sudo cp kube-proxy.kubeconfig /etc/kubernetes/
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
ExecStart=/vagrant/bin/kube-proxy \\
  --bind-address=${NODE_IP} \\
  --hostname-override=${NODE_NAME} \\
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
NAME         STATUS    ROLES     AGE       VERSION
kube-node1   Ready     <none>    22m       v1.10.2
```

都为 Ready 时正常。

### 检查各 Node 上的 Pod IP 连通性

``` bash
$ kubectl get pods  -o wide|grep nginx-ds
nginx-ds-nhfzg   1/1       Running   0          1m        172.30.100.2   kube-node1
```

可见，nginx-ds 的 Pod IP 分别是 `172.30.100.2`、`172.30.20.20`，在所有 Node 上分别 ping 这两个 IP，看是否连通。

### 检查服务 IP 和端口可达性

``` bash
$ kubectl get svc |grep nginx-ds
nginx-ds     NodePort    10.254.106.130   <none>        80:8993/TCP   2m
```

可见：

+ 服务IP：10.254.106.130
+ 服务端口：80
+ NodePort端口：8993

在所有 Node 上执行：

``` bash
$ curl 10.254.106.130 # `kubectl get svc |grep nginx-ds` 输出中的服务 IP
$
```

预期输出 nginx 欢迎页面内容。

### 检查服务的 NodePort 可达性

在所有 Node 上执行：

``` bash
$ export NODE_IP=10.64.3.1 # 当前 Node 的 IP
$ export NODE_PORT=8993 # `kubectl get svc |grep nginx-ds` 输出中 80 端口映射的 NodePort
$ curl ${NODE_IP}:${NODE_PORT}
$
```

预期输出 nginx 欢迎页面内容。

## 参考：
https://kubernetes.io/docs/admin/authentication/
https://kubernetes.io/docs/admin/bootstrap-tokens/
https://kubernetes.io/docs/admin/kubelet-tls-bootstrapping/
https://github.com/linuxkit/kubernetes/pull/68
https://github.com/linuxkit/kubernetes/issues/71