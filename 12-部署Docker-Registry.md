<!-- toc -->

tags: registry, ceph

# 部署私有 docker registry

本文档讲解部署一个 TLS 加密、HTTP Basic 认证、用 ceph rgw 做后端存储的私有 docker registry 步骤，如果使用其它类型的后端存储，则可以从 “创建 docker registry” 节开始；

示例两台机器 IP 如下：

+ ceph rgw: 10.64.3.9
+ docker registry: 10.64.3.7

## 部署 ceph RGW 节点

``` bash
$ ceph-deploy rgw create 10.64.3.9 # rgw 默认监听7480端口
$
```

## 创建测试账号 demo

``` bash
$ radosgw-admin user create --uid=demo --display-name="ceph rgw demo user"
$
```

## 创建 demo 账号的子账号 swift

当前 registry 只支持使用 swift 协议访问 ceph rgw 存储，暂时不支持 s3 协议；

``` bash
$ radosgw-admin subuser create --uid demo --subuser=demo:swift --access=full --secret=secretkey --key-type=swift
$
```

## 创建 demo:swift 子账号的 sercret key

``` bash
$ radosgw-admin key create --subuser=demo:swift --key-type=swift --gen-secret
{
    "user_id": "demo",
    "display_name": "ceph rgw demo user",
    "email": "",
    "suspended": 0,
    "max_buckets": 1000,
    "auid": 0,
    "subusers": [
        {
            "id": "demo:swift",
            "permissions": "full-control"
        }
    ],
    "keys": [
        {
            "user": "demo",
            "access_key": "5Y1B1SIJ2YHKEHO5U36B",
            "secret_key": "nrIvtPqUj7pUlccLYPuR3ntVzIa50DToIpe7xFjT"
        }
    ],
    "swift_keys": [
        {
            "user": "demo:swift",
            "secret_key": "aCgVTx3Gfz1dBiFS4NfjIRmvT0sgpHDP6aa0Yfrh"
        }
    ],
    "caps": [],
    "op_mask": "read, write, delete",
    "default_placement": "",
    "placement_tags": [],
    "bucket_quota": {
        "enabled": false,
        "max_size_kb": -1,
        "max_objects": -1
    },
    "user_quota": {
        "enabled": false,
        "max_size_kb": -1,
        "max_objects": -1
    },
        "temp_url_keys": []
}
```

+ `aCgVTx3Gfz1dBiFS4NfjIRmvT0sgpHDP6aa0Yfrh` 为子账号 demo:swift 的 secret key；

## 创建 docker registry

创建 registry 使用的 TLS 证书

``` bash
$ mdir -p registry/{auth,certs}
$ cat registry-csr.json
{
  "CN": "registry",
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
$ cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes registry-csr.json | cfssljson -bare registry
$ cp registry.pem registry-key.pem registry/certs
$
```

+ 这里复用以前创建的 CA 证书和秘钥文件；

创建 HTTP Baisc 认证文件

``` bash
$ docker run --entrypoint htpasswd registry:2 -Bbn foo foo123  > auth/htpasswd
$ cat auth/htpasswd
foo:$2y$05$I60z69MdluAQ8i1Ka3x3Neb332yz1ioow2C4oroZSOE0fqPogAmZm
```

配置 registry 参数

``` bash
$ export RGW_AUTH_URL="http://10.64.3.9:7480/auth/v1"
$ export RGW_USER="demo:swift"
$ export RGW_SECRET_KEY="aCgVTx3Gfz1dBiFS4NfjIRmvT0sgpHDP6aa0Yfrh"
$ cat > config.yml << EOF
# https://docs.docker.com/registry/configuration/#list-of-configuration-options
version: 0.1
log:
  level: info
  fromatter: text
  fields:
    service: registry

storage:
  cache:
    blobdescriptor: inmemory
  delete:
    enabled: true
  swift:
    authurl: ${RGW_AUTH_URL}
    username: ${RGW_USER}
    password: ${RGW_SECRET_KEY}
    container: registry

auth:
  htpasswd:
    realm: basic-realm
    path: /auth/htpasswd

http:
  addr: 0.0.0.0:8000
  headers:
    X-Content-Type-Options: [nosniff]
  tls:
    certificate: /certs/registry.pem
    key: /certs/registry-key.pem

health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
EOF
```

+ storage.swift 指定后端使用 swfit 接口协议的存储，这里配置的是 ceph rgw 存储参数；
+ auth.htpasswd 指定了 HTTP Basic 认证的 token 文件路径；
+ http.tls 指定了 registry http 服务器的证书和秘钥文件路径；

创建 docker registry

``` bash
$ docker run -d -p 8000:8000 \
    -v $(pwd)/registry/auth/:/auth \
    -v $(pwd)/registry/certs:/certs \
    -v $(pwd)/config.yml:/etc/docker/registry/config.yml \
    --name registry registry:2
```

+ 执行该 docker run 命令的机器 IP 为 10.64.3.7；

## 向 registry push image

将签署 registry 证书的 CA 证书拷贝到 `/etc/docker/certs.d/10.64.3.7:8000` 目录下

``` bash
$ sudo mkdir -p /etc/docker/certs.d/10.64.3.7:8000
$ sudo cp ca.crt /etc/docker/certs.d/10.64.3.7:8000
$
```

登陆私有 registry

``` bash
$ docker login 10.64.3.7:8000
Username: foo
Password:
Login Succeeded
```

登陆信息被写入 `~/.docker/config.json` 文件

``` bash
$ cat ~/.docker/config.json
{
        "auths": {
                "10.64.3.7:8000": {
                        "auth": "Zm9vOmZvbzEyMw=="
                }
        }
}
```

将本地的 image 打上私有 registry 的 tag

``` bash
$ docker tag docker.io/kubernetes/pause 10.64.3.7:8000/zhangjun3/pause
$ docker images |grep pause
docker.io/kubernetes/pause                            latest              f9d5de079539        2 years ago         239.8 kB
10.64.3.7:8000/zhangjun3/pause                        latest              f9d5de079539        2 years ago         239.8 kB
```

将 image push 到私有 registry

``` bash
$ docker push 10.64.3.7:8000/zhangjun3/pause
The push refers to a repository [10.64.3.7:8000/zhangjun3/pause]
5f70bf18a086: Pushed
e16a89738269: Pushed
latest: digest: sha256:9a6b437e896acad3f5a2a8084625fdd4177b2e7124ee943af642259f2f283359 size: 916
```

查看 ceph 上是否已经有 push 的 pause 容器文件

``` bash
$ rados lspools
rbd
.rgw.root
default.rgw.control
default.rgw.data.root
default.rgw.gc
default.rgw.log
default.rgw.users.uid
default.rgw.users.keys
default.rgw.users.swift
default.rgw.buckets.index
default.rgw.buckets.data

$ rados --pool default.rgw.buckets.data ls|grep pause
9c2d5a9d-19e6-4003-90b5-b1cbf15e890d.4310.1_files/docker/registry/v2/repositories/zhangjun3/pause/_layers/sha256/f9d5de0795395db6c50cb1ac82ebed1bd8eb3eefcebb1aa724e01239594e937b/link
9c2d5a9d-19e6-4003-90b5-b1cbf15e890d.4310.1_files/docker/registry/v2/repositories/zhangjun3/pause/_layers/sha256/f72a00a23f01987b42cb26f259582bb33502bdb0fcf5011e03c60577c4284845/link
9c2d5a9d-19e6-4003-90b5-b1cbf15e890d.4310.1_files/docker/registry/v2/repositories/zhangjun3/pause/_layers/sha256/a3ed95caeb02ffe68cdd9fd84406680ae93d633cb16422d00e8a7c22955b46d4/link
9c2d5a9d-19e6-4003-90b5-b1cbf15e890d.4310.1_files/docker/registry/v2/repositories/zhangjun3/pause/_manifests/tags/latest/current/link
9c2d5a9d-19e6-4003-90b5-b1cbf15e890d.4310.1_files/docker/registry/v2/repositories/zhangjun3/pause/_manifests/tags/latest/index/sha256/9a6b437e896acad3f5a2a8084625fdd4177b2e7124ee943af642259f2f283359/link
9c2d5a9d-19e6-4003-90b5-b1cbf15e890d.4310.1_files/docker/registry/v2/repositories/zhangjun3/pause/_manifests/revisions/sha256/9a6b437e896acad3f5a2a8084625fdd4177b2e7124ee943af642259f2f283359/link
```

## 私有 registry 的运维操作

### 查询私有镜像中的 images

``` bash
$ curl  --cacert /etc/docker/certs.d/10.64.3.7\:8000/ca.crt https://10.64.3.7:8000/v2/_catalog
{"repositories":["library/redis","zhangjun3/busybox","zhangjun3/pause","zhangjun3/pause2"]}
```

### 查询某个镜像的 tags 列表

``` bash
$ curl  --cacert /etc/docker/certs.d/10.64.3.7\:8000/ca.crt https://10.64.3.7:8000/v2/zhangjun3/busybox/tags/list
{"name":"zhangjun3/busybox","tags":["latest"]}
```

### 获取 image 或 layer 的 digest

向 `v2/<repoName>/manifests/<tagName>` 发 GET 请求，从响应的头部 `Docker-Content-Digest` 获取 image digest，从响应的 body 的 `fsLayers.blobSum` 中获取 layDigests;

注意，必须包含请求头：`Accept: application/vnd.docker.distribution.manifest.v2+json`：

``` bash
$ curl -v -H "Accept: application/vnd.docker.distribution.manifest.v2+json" --cacert /etc/docker/certs.d/10.64.3.7\:8000/ca.crt https://10.64.3.7:8000/v2/zhangjun3/busybox/manifests/latest

> GET /v2/zhangjun3/busybox/manifests/latest HTTP/1.1
> User-Agent: curl/7.29.0
> Host: 10.64.3.7:8000
> Accept: application/vnd.docker.distribution.manifest.v2+json
>
< HTTP/1.1 200 OK
< Content-Length: 527
< Content-Type: application/vnd.docker.distribution.manifest.v2+json
< Docker-Content-Digest: sha256:68effe31a4ae8312e47f54bec52d1fc925908009ce7e6f734e1b54a4169081c5
< Docker-Distribution-Api-Version: registry/2.0
< Etag: "sha256:68effe31a4ae8312e47f54bec52d1fc925908009ce7e6f734e1b54a4169081c5"
< X-Content-Type-Options: nosniff
< Date: Tue, 21 Mar 2017 15:19:42 GMT
<
{
   "schemaVersion": 2,
   "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
   "config": {
      "mediaType": "application/vnd.docker.container.image.v1+json",
      "size": 1465,
      "digest": "sha256:00f017a8c2a6e1fe2ffd05c281f27d069d2a99323a8cd514dd35f228ba26d2ff"
   },
   "layers": [
      {
         "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
         "size": 701102,
         "digest": "sha256:04176c8b224aa0eb9942af765f66dae866f436e75acef028fe44b8a98e045515"
      }
   ]
}
```

### 删除 image

向 `/v2/<name>/manifests/<reference>` 发送 DELETE 请求，reference 为上一步返回的 Docker-Content-Digest 字段内容：

``` bash
$ curl -X DELETE  --cacert /etc/docker/certs.d/10.64.3.7\:8000/ca.crt https://10.64.3.7:8000/v2/zhangjun3/busybox/manifests/sha256:68effe31a4ae8312e47f54bec52d1fc925908009ce7e6f734e1b54a4169081c5
$
```

### 删除 layer

向 `/v2/<name>/blobs/<digest>`发送 DELETE 请求，其中 digest 是上一步返回的 `fsLayers.blobSum` 字段内容：

``` bash
$ curl -X DELETE  --cacert /etc/docker/certs.d/10.64.3.7\:8000/ca.crt https://10.64.3.7:8000/v2/zhangjun3/busybox/blobs/sha256:a3ed95caeb02ffe68cdd9fd84406680ae93d633cb16422d00e8a7c22955b46d4
$ curl -X DELETE  --cacert /etc/docker/certs.d/10.64.3.7\:8000/ca.crt https://10.64.3.7:8000/v2/zhangjun3/busybox/blobs/sha256:04176c8b224aa0eb9942af765f66dae866f436e75acef028fe44b8a98e045515
$
```