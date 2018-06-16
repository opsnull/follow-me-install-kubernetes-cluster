查看 nodes metrics 时，提示无权限：

$ kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes" | jq .
Error from server (Forbidden): nodes.metrics.k8s.io is forbidden: User "system:anonymous" cannot list nodes.metrics.k8s.io at the cluster scope.


kube-apiserver 的日志：

vagrant@kube-node1:/opt/k8s/k8s-prometheus-adapter/deploy$ sudo journalctl -u kube-apiserver -f|grep metrics-server
May 10 12:17:21 kube-node1 kube-apiserver[13785]: I0510 12:17:21.805131   13785 wrap.go:42] POST /apis/authorization.k8s.io/v1beta1/subjectaccessreviews: (308.935µs) 201 [[metrics-server/v0.0.0 (linux/amd64) kubernetes/$Format] 172.30.21.2:38330]
May 10 12:17:21 kube-node1 kube-apiserver[13785]: I0510 12:17:21.989828   13785 wrap.go:42] POST /apis/authorization.k8s.io/v1beta1/subjectaccessreviews: (1.418764ms) 201 [[metrics-server/v0.0.0 (linux/amd64) kubernetes/$Format] 172.30.21.2:38330]


原因：kube-apiserver 缺少了 --proxy-client-cert-file --proxy-client-key-file 配置参数。
vagrant@kube-node1:/opt/k8s/kubernetes/cluster/addons/metrics-server$ cat metrics-server-csr.json
{
  "CN": "aggregator",
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

vagrant@kube-node1:/opt/k8s/kubernetes/cluster/addons/metrics-server$ sudo /opt/k8s/bin/cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem   -ca-key=/etc/kubernetes/ssl/ca-key.pem   -config=/etc/kubernetes/ssl/ca-config.json   -profile=kubernetes metrics-server-csr.json| sudo /opt/k8s/bin/cfssljson -bare metrics-server

sudo cp metrics-server-key.pem metrics-server.pem /etc/kubernetes/ssl/

修改 kube-apiserver.service，添加如下配置：
  --requestheader-allowed-names="aggregator" \
  --requestheader-extra-headers-prefix="X-Remote-Extra-" \
  --requestheader-group-headers=X-Remote-Group \
  --requestheader-username-headers=X-Remote-User \
  --requestheader-client-ca-file=/etc/kubernetes/ssl/ca.pem \
  --proxy-client-cert-file=/etc/kubernetes/ssl/metrics-server.pem \
  --proxy-client-key-file=/etc/kubernetes/ssl/metrics-server-key.pem \

注意：--proxy-client-cert-file 证书的 CN 应该与  --requestheader-allowed-names="aggregator" 一致。且 --proxy-client-cert-file 应该被 --requestheader-client-ca-file 签名。



I0616 09:15:26.364032       1 heapster.go:71] /metrics-server --source=kubernetes.summary_api:''
I0616 09:15:26.364155       1 heapster.go:72] Metrics Server version v0.2.1
I0616 09:15:26.364706       1 configs.go:61] Using Kubernetes client with master "https://10.254.0.1:443" and version 
I0616 09:15:26.364744       1 configs.go:62] Using kubelet port 10255
I0616 09:15:26.462294       1 heapster.go:128] Starting with Metric Sink
I0616 09:15:39.662170       1 serving.go:308] Generated self-signed cert (apiserver.local.config/certificates/apiserver.crt, apiserver.local.config/certificates/apiserver.key)
I0616 09:15:52.562162       1 heapster.go:101] Starting Heapster API server...
[restful] 2018/06/16 09:15:52 log.go:33: [restful/swagger] listing is available at https:///swaggerapi
[restful] 2018/06/16 09:15:52 log.go:33: [restful/swagger] https:///swaggerui/ is mapped to folder /swagger-ui/
I0616 09:15:52.662217       1 serve.go:85] Serving securely on 0.0.0.0:443
E0616 09:16:05.060672       1 summary.go:97] error while getting metrics summary from Kubelet kube-node2(172.27.129.111:10255): Get http://172.27.129.111:10255/stats/summary/: dial tcp 172.27.129.111:10255: getsockopt: connection refused
E0616 09:17:05.013460       1 summary.go:97] error while getting metrics summary from Kubelet kube-node2(172.27.129.111:10255): Get http://172.27.129.111:10255/stats/summary/: dial tcp 172.27.129.111:10255: getsockopt: connection refused
E0616 09:18:05.018258       1 summary.go:97] error while getting metrics summary from Kubelet kube-node2(172.27.129.111:10255): Get http://172.27.129.111:10255/stats/summary/: dial tcp 172.27.129.111:10255: getsockopt: connection refused

解决办法：metrics-server deploy 中添加 kubelet 配置参数：
$ diff metrics-server-deployment.yaml.orig metrics-server-deployment.yaml
51c51
<         image: mirrorgooglecontainers/metrics-server-amd64:v0.2.1
---
>         image: k8s.gcr.io/metrics-server-amd64:v0.2.1
54c54
<         - --source=kubernetes.summary_api:''
---
>         - --source=kubernetes.summary_api:https://kubernetes.default?kubeletHttps=true&kubeletPort=10250
60c60
<         image: siriuszg/addon-resizer:1.8.1
---
>         image: k8s.gcr.io/addon-resizer:1.8.1


E0616 09:58:05.013949       1 summary.go:97] error while getting metrics summary from Kubelet kube-node2(172.27.129.111:10250): request failed - "403 Forbidden", response: "Forbidden (user=system:serviceaccount:kube-system:metrics-server, verb=get, resource=nodes, subresource=stats)"
E0616 09:59:05.020895       1 summary.go:97] error while getting metrics summary from Kubelet kube-node2(172.27.129.111:10250): request failed - "403 Forbidden", response: "Forbidden (user=system:serviceaccount:kube-system:metrics-server, verb=get, resource=nodes, subresource=stats)"

解决办法：授予 serviceaccount kube-system:metrics-server 访问 kubelet API 的权限；
新建一个 ClusterRoleBindings 定义文件，授予相关权限：

``` bash
$ cat auth-kubelet.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: metrics-server:system:kubelet-api-admin
  labels:
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kubelet-api-admin
subjects:
- kind: ServiceAccount
  name: metrics-server
  namespace: kube-system
```