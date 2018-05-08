<!-- toc -->

tags: kubedns

# 部署 kubedns 插件

## 修改配置文件

官方文件目录：`kubernetes/cluster/addons/dns`

```bash
$ pwd
/vagrant/kubernetes/cluster/addons/dns
$ cp coredns.yaml.base coredns.yaml
$ diff coredns.yaml.base coredns.yaml
61c61
<         kubernetes __PILLAR__DNS__DOMAIN__ in-addr.arpa ip6.arpa {
---
>         kubernetes cluster.local. in-addr.arpa ip6.arpa {
153c153
<   clusterIP: __PILLAR__DNS__SERVER__
---
>   clusterIP: 10.254.0.2
```

## 创建 coreDNS

``` bash
$ kubectl create -f coredns.yaml
serviceaccount "coredns" created
clusterrole.rbac.authorization.k8s.io "system:coredns" created
clusterrolebinding.rbac.authorization.k8s.io "system:coredns" created
configmap "coredns" created
deployment.extensions "coredns" created
service "coredns" created
```

## 检查 kubedns 功能

``` bash
$ kubectl get all --namespace kube-system
NAME                           READY     STATUS    RESTARTS   AGE
pod/coredns-77c989547b-9mx5z   1/1       Running   0          59s
pod/coredns-77c989547b-rf4zm   1/1       Running   0          59s

NAME              TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)         AGE
service/coredns   ClusterIP   10.254.0.2   <none>        53/UDP,53/TCP   59s

NAME                      DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/coredns   2         2         2            2           59s

NAME                                 DESIRED   CURRENT   READY     AGE
replicaset.apps/coredns-77c989547b   2         2         2         59s
```

新建一个 Deployment

``` bash
$ cat  my-nginx.yaml
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: my-nginx
spec:
  replicas: 2
  template:
    metadata:
      labels:
        run: my-nginx
    spec:
      containers:
      - name: my-nginx
        image: nginx:1.7.9
        ports:
        - containerPort: 80
$ kubectl create -f my-nginx.yaml
$
```

Export 该 Deployment, 生成 `my-nginx` 服务

``` bash
$ kubectl expose deploy my-nginx
$ kubectl get services --all-namespaces |grep my-nginx
default       my-nginx     ClusterIP   10.254.63.136    <none>        80/TCP          6s
```

创建另一个 Pod，查看 `/etc/resolv.conf` 是否包含 `kubelet` 配置的 `--cluster-dns` 和 `--cluster-domain`，是否能够将服务 `my-nginx` 解析到上面显示的 Cluster IP `10.254.63.136`

``` bash
$ cat pod-nginx.yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  containers:
  - name: nginx
    image: nginx:1.7.9
    ports:
    - containerPort: 80
$ kubectl create -f pod-nginx.yaml
$ kubectl exec  nginx -i -t -- /bin/bash
root@nginx:/# cat /etc/resolv.conf
nameserver 10.254.0.2
search default.svc.cluster.local. svc.cluster.local. cluster.local.
options ndots:5

root@nginx:/# ping my-nginx
PING my-nginx.default.svc.cluster.local (10.254.63.136): 48 data bytes
^C--- my-nginx.default.svc.cluster.local ping statistics ---
4 packets transmitted, 0 packets received, 100% packet loss

root@nginx:/# ping kubernetes
PING kubernetes.default.svc.cluster.local (10.254.0.1): 48 data bytes
^C--- kubernetes.default.svc.cluster.local ping statistics ---
1 packets transmitted, 0 packets received, 100% packet loss

root@nginx:/# ping coredns.kube-system.svc.cluster.local  # 注意：不是 kube-dns.kube-system.svc.cluster.local
PING kube-dns.kube-system.svc.cluster.local (10.254.0.2): 48 data bytes
^C--- kube-dns.kube-system.svc.cluster.local ping statistics ---
1 packets transmitted, 0 packets received, 100% packet loss
```

## 参考
https://community.infoblox.com/t5/Community-Blog/CoreDNS-for-Kubernetes-Service-Discovery/ba-p/8187
https://coredns.io/2017/03/01/coredns-for-kubernetes-service-discovery-take-2/
https://www.cnblogs.com/boshen-hzb/p/7511432.html
https://github.com/kubernetes/kubernetes/tree/master/cluster/addons/dns