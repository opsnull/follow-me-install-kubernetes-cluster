<!-- toc -->

tags: TLS, CA

# 创建 TLS 证书和秘钥

`kubernetes` 系统各组件需要使用 `TLS` 证书对通信进行加密，本文档使用 `CloudFlare` 的 PKI 工具集 [cfssl](https://github.com/cloudflare/cfssl) 来生成 Certificate Authority (CA) 和其它证书。

生成的 CA 证书和秘钥文件如下：

+ ca-key.pem
+ ca.pem
+ kubernetes-key.pem
+ kubernetes.pem
+ kube-proxy.pem
+ kube-proxy-key.pem
+ admin.pem
+ admin-key.pem

使用证书的组件如下：

+ etcd：使用 ca.pem、kubernetes-key.pem、kubernetes.pem；
+ kube-apiserver：使用 ca.pem、kubernetes-key.pem、kubernetes.pem；
+ kubelet：使用 ca.pem；
+ kube-proxy：使用 ca.pem、kube-proxy-key.pem、kube-proxy.pem；
+ kubectl：使用 ca.pem、admin-key.pem、admin.pem；

`kube-controller`、`kube-scheduler` 当前需要和 `kube-apiserver` 部署在同一台机器上且使用非安全端口通信，故不需要证书。

kubernetes 1.4 开始支持 `TLS Bootstrapping` 功能，由 `kube-apiserver` 为客户端生成 TLS 证书，这样就不需要为每个客户端生成证书（该功能**目前仅支持 `kubelet`**，所以本文档没有为 kubelet 生成证书和秘钥）。

## 安装 `CFSSL`

``` bash
$ mkdir -p /root/local/bin/

$ wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
$ chmod +x cfssl_linux-amd64
$ sudo mv cfssl_linux-amd64 /root/local/bin/cfssl

$ wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
$ chmod +x cfssljson_linux-amd64
$ sudo mv cfssljson_linux-amd64 /root/local/bin/cfssljson

$ wget https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64
$ chmod +x cfssl-certinfo_linux-amd64
$ sudo mv cfssl-certinfo_linux-amd64 /root/local/bin/cfssl-certinfo

$ export PATH=/root/local/bin:$PATH
$ mkdir ssl
$ cd ssl
$ cfssl print-defaults config > config.json
$ cfssl print-defaults csr > csr.json
$
```

## 创建 CA (Certificate Authority)

创建 CA 配置文件：

``` bash
$ cat ca-config.json
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ],
        "expiry": "8760h"
      }
    }
  }
}
```

+ `ca-config.json`：可以定义多个 profiles，分别指定不同的过期时间、使用场景等参数；后续在签名证书时使用某个 profile；
+ `signing`：表示该证书可用于签名其它证书；生成的 ca.pem 证书中 `CA=TRUE`；
+ `server auth`：表示 client 可以用该 CA 对 server 提供的证书进行验证；
+ `client auth`：表示 server 可以用该 CA 对 client 提供的证书进行验证；

创建 CA 证书签名请求：

``` bash
$ cat ca-csr.json
{
  "CN": "kubernetes",
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

+ "CN"：`Common Name`，kube-apiserver 从证书中提取该字段作为请求的用户名 (User Name)；浏览器使用该字段验证网站是否合法；
+ "O"：`Organization`，kube-apiserver 从证书中提取该字段作为请求用户所属的组 (Group)；

生成 CA 证书和私钥：

``` bash
$ cfssl gencert -initca ca-csr.json | cfssljson -bare ca
$ ls ca*
ca-config.json  ca.csr  ca-csr.json  ca-key.pem  ca.pem
$
```

## 创建 kubernetes 证书

创建 kubernetes 证书签名请求：

``` bash
$ cat kubernetes-csr.json
{
  "CN": "kubernetes",
  "hosts": [
    "127.0.0.1",
    "10.64.3.7",
    "10.64.3.8",
    "10.66.3.86",
    "10.254.0.1",
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
      "OU": "System"
    }
  ]
}
```

+ 如果 hosts 字段不为空则需要指定授权使用该证书的 **IP 或域名列表**，由于该证书后续被 `etcd` 集群和 `kubernetes master` 集群使用，所以上面分别指定了 `etcd` 集群、`kubernetes master` 集群的主机 IP；
+ 还需要添加 kube-apiserver 注册的名为 `kubernetes` 的服务 IP (Service Cluster IP)，一般是 kube-apiserver `--service-cluster-ip-range` 选项值指定的网段的**第一个IP**，如 "10.254.0.1"；

  ``` bash
  $ kubectl get svc kubernetes
  NAME         CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
  kubernetes   10.254.0.1   <none>        443/TCP   1d
  ```

生成 kubernetes 证书和私钥：

``` bash
$ cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kubernetes-csr.json | cfssljson -bare kubernetes
$ ls kubernetes*
kubernetes.csr  kubernetes-csr.json  kubernetes-key.pem  kubernetes.pem
```

或者直接在命令行上指定相关参数：

``` bash
$ echo '{"CN":"kubernetes","hosts":[""],"key":{"algo":"rsa","size":2048}}' | cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes -hostname="127.0.0.1,10.64.3.7,10.254.0.1,kubernetes,kubernetes.default" - | cfssljson -bare kubernetes
$
```

## 创建 admin 证书

创建 admin 证书签名请求：

``` bash
$ cat admin-csr.json
{
  "CN": "admin",
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
      "O": "system:masters",
      "OU": "System"
    }
  ]
}
```

+ 后续 `kube-apiserver` 使用 `RBAC` 对客户端(如 `kubelet`、`kube-proxy`、`Pod`)请求进行授权；
+ `kube-apiserver` 预定义了一些 `RBAC` 使用的 `RoleBindings`，如 Group `system:masters` 与 Role `cluster-admin` 绑定，该 Role 授予了调用`kube-apiserver` **所有 API**的权限；
+ O 指定该证书的 Group 为 `system:masters`，`kubelet` 使用该证书访问 `kube-apiserver` 时 ，由于证书被 CA 签名，所以认证通过，同时由于证书用户组为经过预授权的 `system:masters`，所以被授予访问所有 API 的权限；

生成 admin 证书和私钥：

``` bash
$ cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes admin-csr.json | cfssljson -bare admin
$ ls admin*
admin.csr  admin-csr.json  admin-key.pem  admin.pem
```

## 创建 kube-proxy 证书

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
+ `kube-apiserver` 预定义的 RoleBinding  将User `system:kube-proxy` 与 Role `system:node-proxier` 绑定，该 Role 授予了调用 `kube-apiserver` Proxy 相关 API 的权限；

生成 kube-proxy 客户端证书和私钥：

``` bash
$ cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes  kube-proxy-csr.json | cfssljson -bare kube-proxy
$ ls kube-proxy*
kube-proxy.csr  kube-proxy-csr.json  kube-proxy-key.pem  kube-proxy.pem
```

## 校验证书

以校验 kubernetes 证书为例：

### 使用 `openssl` 命令

``` bash
$ openssl x509  -noout -text -in  kubernetes.pem
...
    Signature Algorithm: sha256WithRSAEncryption
        Issuer: C=CN, ST=BeiJing, L=BeiJing, O=k8s, OU=System, CN=Kubernetes
        Validity
            Not Before: Apr  5 05:36:00 2017 GMT
            Not After : Apr  5 05:36:00 2018 GMT
        Subject: C=CN, ST=BeiJing, L=BeiJing, O=k8s, OU=System, CN=kubernetes
...
        X509v3 extensions:
            X509v3 Key Usage: critical
                Digital Signature, Key Encipherment
            X509v3 Extended Key Usage:
                TLS Web Server Authentication, TLS Web Client Authentication
            X509v3 Basic Constraints: critical
                CA:FALSE
            X509v3 Subject Key Identifier:
                DD:52:04:43:10:13:A9:29:24:17:3A:0E:D7:14:DB:36:F8:6C:E0:E0
            X509v3 Authority Key Identifier:
                keyid:44:04:3B:60:BD:69:78:14:68:AF:A0:41:13:F6:17:07:13:63:58:CD

            X509v3 Subject Alternative Name:
                DNS:kubernetes, DNS:kubernetes.default, DNS:kubernetes.default.svc, DNS:kubernetes.default.svc.cluster, DNS:kubernetes.default.svc.cluster.local, IP Address:127.0.0.1, IP Address:10.64.3.7, IP Address:10.254.0.1
...
```

+ 确认 `Issuer` 字段的内容和 `ca-csr.json` 一致；
+ 确认 `Subject` 字段的内容和 `kubernetes-csr.json` 一致；
+ 确认 `X509v3 Subject Alternative Name` 字段的内容和 `kubernetes-csr.json` 一致；
+ 确认 `X509v3 Key Usage、Extended Key Usage` 字段的内容和 `ca-config.json` 中 `kubernetes` profile 一致；

### 使用 `cfssl-certinfo` 命令

``` bash
$ cfssl-certinfo -cert kubernetes.pem
...
{
  "subject": {
    "common_name": "kubernetes",
    "country": "CN",
    "organization": "k8s",
    "organizational_unit": "System",
    "locality": "BeiJing",
    "province": "BeiJing",
    "names": [
      "CN",
      "BeiJing",
      "BeiJing",
      "k8s",
      "System",
      "kubernetes"
    ]
  },
  "issuer": {
    "common_name": "Kubernetes",
    "country": "CN",
    "organization": "k8s",
    "organizational_unit": "System",
    "locality": "BeiJing",
    "province": "BeiJing",
    "names": [
      "CN",
      "BeiJing",
      "BeiJing",
      "k8s",
      "System",
      "Kubernetes"
    ]
  },
  "serial_number": "174360492872423263473151971632292895707129022309",
  "sans": [
    "kubernetes",
    "kubernetes.default",
    "kubernetes.default.svc",
    "kubernetes.default.svc.cluster",
    "kubernetes.default.svc.cluster.local",
    "127.0.0.1",
    "10.64.3.7",
    "10.64.3.8",
    "10.66.3.86",
    "10.254.0.1"
  ],
  "not_before": "2017-04-05T05:36:00Z",
  "not_after": "2018-04-05T05:36:00Z",
  "sigalg": "SHA256WithRSA",
...
```

## 分发证书

将生成的证书和秘钥文件（后缀名为`.pem`）拷贝到**所有机器**的 `/etc/kubernetes/ssl` 目录下:

``` bash
$ sudo mkdir -p /etc/kubernetes/ssl
$ sudo cp *.pem /etc/kubernetes/ssl
$
```

参考

+ [Generate self-signed certificates](https://coreos.com/os/docs/latest/generate-self-signed-certificates.html)
+ [Setting up a Certificate Authority and Creating TLS Certificates](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/02-certificate-authority.md)
+ [Client Certificates V/s Server Certificates](https://blogs.msdn.microsoft.com/kaushal/2012/02/17/client-certificates-vs-server-certificates/)
