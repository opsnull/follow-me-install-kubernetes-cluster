<!-- toc -->

tags: kubeconfig, token.csv, bootstrap.kubeconfig, kube-proxy.kubeconfig

# 配置 kubeconfig 文件

`kubelet`、`kube-proxy` 等 Node 节点上的进程与 Master 机器的 `kube-apiserver` 进程通信时需要提供认证和授权信息，这些信息保存在 kubeconfig 文件中。

本文档介绍配置 `kubelet`、`kube-proxy` 进程使用的 kubeconfig 文件步骤。

## 使用的变量

本文档用到的变量定义如下：

``` bash
$ export MASTER_IP=10.64.3.7 # 替换为 kubernetes master 集群任一机器 IP
$ export KUBE_APISERVER="https://${MASTER_IP}:6443"
$ export BOOTSTRAP_TOKEN=$(head -c 16 /dev/urandom | od -An -t x | tr -d ' ')
$
```

## 创建 TLS Bootstrapping Token

kubernetes 1.4 开始支持由 `kube-apiserver` 为客户端生成 TLS 证书的 `TLS Bootstrapping` 功能，这样就不需要为每个客户端生成证书了（该功能**目前仅支持 `kubelet`**）。

客户端请求 TLS Bootstrapping 时需要提供包含认证 token 的 boostrap kubeconfig 文件(参考 [部署 Node 节点](07-node.md))。

``` bash
$ cat > token.csv <<EOF
${BOOTSTRAP_TOKEN},kubelet-bootstrap,10001,"system:kubelet-bootstrap"
EOF
```

## 分发 token.csv 文件

将 token.csv 文件拷贝到**所有机器**（Master 和 Node）的 `/etc/kubernetes/` 目录：

``` bash
$ sudo cp token.csv /etc/kubernetes/
$
```

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
```

+ `--embed-certs` 为 `true` 时表示将 `certificate-authority` 证书写入到生成的 `bootstrap.kubeconfig` 文件中；
+ 设置客户端认证参数时**没有**指定秘钥和证书，后续由 `kube-apiserver` 自动生成；


## 创建 kube-proxy kubeconfig 文件

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
```

+ 设置集群参数和客户端认证参数时 `--embed-certs` 都为 `true`，这会将 `certificate-authority`、`client-certificate` 和 `client-key` 指向的证书文件内容写入到生成的 `kube-proxy.kubeconfig` 文件中；
+ `kube-proxy.pem` 证书中 CN 为 `system:kube-proxy`，`kube-apiserver` 预定义的 RoleBinding `cluster-admin` 将User `system:kube-proxy` 与 Role `system:node-proxier` 绑定，该 Role 授予了调用 `kube-apiserver` Proxy 相关 API 的权限；

## 分发 kubeconfig 文件

将两个 kubeconfig 文件拷贝到所有 Node 机器的 `/etc/kubernetes/` 目录：

``` bash
$ sudo cp bootstrap.kubeconfig kube-proxy.kubeconfig /etc/kubernetes/
$
```