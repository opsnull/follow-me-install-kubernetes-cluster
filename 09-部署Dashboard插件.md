<!-- toc -->

tags: dashboard

# 部署 dashboard 插件

官方文件目录：`kubernetes/cluster/addons/dashboard`

``` bash
$ pwd
/vagrant/kubernetes/cluster/addons/dashboard
```

## 配置dashboard-service

``` bash
$ cp dashboard-controller.yaml{,.bak}
$ diff dashboard-controller.yaml{,.bak}
33c33
<         image: siriuszg/kubernetes-dashboard-amd64:v1.8.3
---
>         image: k8s.gcr.io/kubernetes-dashboard-amd64:v1.8.3

$ cp dashboard-service.yaml{,.orig}
$ diff dashboard-service.yaml.orig dashboard-service.yaml
10a11
>   type: NodePort
```
+ 指定端口类型为 NodePort，这样外界可以通过地址 nodeIP:nodePort 访问 dashboard；

## 执行所有定义文件

``` bash
$ pwd
/root/kubernetes/cluster/addons/dashboard
$ ls *.yaml
dashboard-configmap.yaml  dashboard-controller.yaml  dashboard-rbac.yaml  dashboard-secret.yaml  dashboard-service.yaml
$ kubectl create -f  .
configmap "kubernetes-dashboard-settings" created
serviceaccount "kubernetes-dashboard" created
deployment.apps "kubernetes-dashboard" created
role.rbac.authorization.k8s.io "kubernetes-dashboard-minimal" created
rolebinding.rbac.authorization.k8s.io "kubernetes-dashboard-minimal" created
secret "kubernetes-dashboard-certs" created
secret "kubernetes-dashboard-key-holder" created
service "kubernetes-dashboard" created

$ kubectl get roles --namespace kube-system|grep dashboard
kubernetes-dashboard-minimal                     47m

$ kubectl get rolebindings --namespace kube-system|grep dashboard
kubernetes-dashboard-minimal                     48m

$ kubectl describe roles --namespace kube-system kubernetes-dashboard-minimal
Name:         kubernetes-dashboard-minimal
Labels:       addonmanager.kubernetes.io/mode=Reconcile
              k8s-app=kubernetes-dashboard
Annotations:  <none>
PolicyRule:
  Resources       Non-Resource URLs  Resource Names                     Verbs
  ---------       -----------------  --------------                     -----
  configmaps      []                 [kubernetes-dashboard-settings]    [get update]
  secrets         []                 [kubernetes-dashboard-certs]       [get update delete]
  secrets         []                 [kubernetes-dashboard-key-holder]  [get update delete]
  services        []                 [heapster]                         [proxy]
  services/proxy  []                 [heapster]                         [get]
  services/proxy  []                 [http:heapster:]                   [get]
  services/proxy  []                 [https:heapster:]                  [get]

$ kubectl describe rolebindings --namespace kube-system kubernetes-dashboard-minimal
Name:         kubernetes-dashboard-minimal
Labels:       addonmanager.kubernetes.io/mode=Reconcile
              k8s-app=kubernetes-dashboard
Annotations:  <
  Kind:  Role
  Name:  kubernetes-dashboard-minimal
Subjects:
  Kind            Name                  Namespace
  ----            ----                  ---------
  ServiceAccount  kubernetes-dashboard  kube-system
```

## 检查执行结果

查看分配的 NodePort

``` bash
$ kubectl get deployment kubernetes-dashboard  -n kube-system
NAME                   DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
kubernetes-dashboard   1         1         1            1           4m

$ kubectl --namespace kube-system get pods|grep dashboard
kubernetes-dashboard-65f7b4f486-6x775   1/1       Running   0          3m

$ kubectl get services kubernetes-dashboard -n kube-system
NAME                   CLUSTER-IP       EXTERNAL-IP   PORT(S)        AGE
kubernetes-dashboard   NodePort   10.254.196.244   <none>        443:8733/TCP   3m
```

+ NodePort 8733 映射到 dashboard pod 443 端口；

dashboard 的  --authentication-mode 支持 token、basic，默认为 token。如果使用 basic，则  kube-apiserver 必须配置 '--authorization-mode=ABAC' 和 '--basic-auth-file' 选项。

查看 dashboard 支持的命令行参数方法如下：

``` bash
$ kubectl exec --namespace kube-system -it kubernetes-dashboard-65f7b4f486-6x775 -- /dashboard --help
2018/05/07 04:05:02 Starting overwatch
Usage of /dashboard:
      --alsologtostderr                   log to standard error as well as files
      --apiserver-host string             The address of the Kubernetes Apiserver to connect to in the format of protocol://address:port, e.g., http://localhost:8080. If not specified, the assumption is that the binary runs inside a Kubernetes cluster and local discovery is attempted.
      --authentication-mode stringSlice   Enables authentication options that will be reflected on login screen. Supported values: token, basic. Default: token.Note that basic option should only be used if apiserver has '--authorization-mode=ABAC' and '--basic-auth-file' flags set. (default [token])
      --auto-generate-certificates        When set to true, Dashboard will automatically generate certificates used to serve HTTPS. Default: false.
      --bind-address ip                   The IP address on which to serve the --secure-port (set to 0.0.0.0 for all interfaces). (default 0.0.0.0)
      --default-cert-dir string           Directory path containing '--tls-cert-file' and '--tls-key-file' files. Used also when auto-generating certificates flag is set. (default "/certs")
      --disable-settings-authorizer       When enabled, Dashboard settings page will not require user to be logged in and authorized to access settings page.
      --enable-insecure-login             When enabled, Dashboard login view will also be shown when Dashboard is not served over HTTPS. Default: false.
      --heapster-host string              The address of the Heapster Apiserver to connect to in the format of protocol://address:port, e.g., http://localhost:8082. If not specified, the assumption is that the binary runs inside a Kubernetes cluster and service proxy will be used.
      --insecure-bind-address ip          The IP address on which to serve the --port (set to 0.0.0.0 for all interfaces). (default 127.0.0.1)
      --insecure-port int                 The port to listen to for incoming HTTP requests. (default 9090)
      --kubeconfig string                 Path to kubeconfig file with authorization and master location information.
      --log_backtrace_at traceLocation    when logging hits line file:N, emit a stack trace (default :0)
      --log_dir string                    If non-empty, write log files in this directory
      --logtostderr                       log to standard error instead of files
      --metric-client-check-period int    Time in seconds that defines how often configured metric client health check should be run. Default: 30 seconds. (default 30)
      --port int                          The secure port to listen to for incoming HTTPS requests. (default 8443)
      --stderrthreshold severity          logs at or above this threshold go to stderr (default 2)
      --system-banner string              When non-empty displays message to Dashboard users. Accepts simple HTML tags. Default: ''.
      --system-banner-severity string     Severity of system banner. Should be one of 'INFO|WARNING|ERROR'. Default: 'INFO'. (default "INFO")
      --tls-cert-file string              File containing the default x509 Certificate for HTTPS.
      --tls-key-file string               File containing the default x509 private key matching --tls-cert-file.
      --token-ttl int                     Expiration time (in seconds) of JWE tokens generated by dashboard. Default: 15 min. 0 - never expires (default 900)
  -v, --v Level                           log level for V logs
      --vmodule moduleSpec                comma-separated list of pattern=N settings for file-filtered logging
command terminated with exit code 2
```

## 访问 dashboard

1. kubernetes-dashboard 服务暴露了 NodePort，可以使用 `http://NodeIP:nodePort` 地址访问 dashboard；
1. 通过 kube-apiserver 访问 dashboard；
1. 通过 kubectl proxy 访问 dashboard：

对于本教程，使用的是 Vargrant + VirtualBox，需要启用 VirtualBox 的 ForworadPort 功能将虚机监听的端口和 Host 的本地端口绑定。Vagrant 中已经配置了这个端口转发绑定。
对于正在运行的虚机，也可以通过 VirtualBox 的界面进行配置：

![virtualbox-1](./images/virtualbox-1.png)
![virtualbox-2](./images/virtualbox-2.png)

### 通过 kubectl proxy 访问 dashboard

启动代理

``` bash
$ kubectl proxy --address='10.64.3.1' --port=8086 --accept-hosts='^*$'
Starting to serve on 10.64.3.7:8086
```

+ 需要指定 `--accept-hosts` 选项，否则浏览器访问 dashboard 页面时提示 “Unauthorized”；

浏览器访问 URL：`http://10.64.3.1:8086/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy`
对于 virtuabox 做了端口映射： `http://127.0.0.1:8086/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy`

### 通过 kube-apiserver 访问dashboard

获取集群服务地址列表

``` bash
$ kubectl cluster-info
Kubernetes master is running at https://10.64.3.1:6443
CoreDNS is running at https://10.64.3.1:6443/api/v1/namespaces/kube-system/services/coredns:dns/proxy
kubernetes-dashboard is running at https://10.64.3.1:6443/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy
```

由于 kube-apiserver 开启了 RBAC 授权，而浏览器访问 kube-apiserver 的时候使用的是匿名证书，所以访问安全端口会导致授权失败。这里需要使用**非安全**端口访问 kube-apiserver：

浏览器访问 URL：`http://10.64.3.1:8080/api/v1/proxy/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy`
对于 virtuabox 做了端口映射： `http://127.0.0.1:8080/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy`

![dashboard-login](./images/dashboard-login.png)

## 创建登录 Dashboard 的 token 和 KubeConfig 配置文件

上面提到，Dashboard 默认只支持 token 认证，所以如果使用 KubeConfig 文件，需要在该文件中指定 token，不支持使用 client 证书认证。

### 创建登录 token

``` bash
$ kubectl create sa dashboard-admin -n kube-system
$ kubectl create clusterrolebinding dashboard-admin --clusterrole=cluster-admin --serviceaccount=kube-system:dashboard-admin
$ ADMIN_SECRET=$(kubectl get secrets -n kube-system | grep dashboard-admin | awk '{print $1}')
$ DASHBOARD_LOGIN_TOKEN=$(kubectl describe secret -n kube-system ${ADMIN_SECRET} | grep -E '^token' | awk '{print $2}')
$ echo ${DASHBOARD_LOGIN_TOKEN}
```

使用输出的 token 登录 Dashboard。

### 使用创建的 token 创建 KubeConfig 文件

``` bash
$ export MASTER_IP=10.64.3.1 # 替换为 kubernetes master 集群任一机器 IP
$ export KUBE_APISERVER="https://${MASTER_IP}:6443"
$ # 设置集群参数
$ kubectl config set-cluster kubernetes \
  --certificate-authority=/etc/kubernetes/ssl/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=dashboard.kubeconfig

$ # 设置客户端认证参数
$ kubectl config set-credentials dashboard_user \
  --token=${DASHBOARD_LOGIN_TOKEN} \
  --kubeconfig=dashboard.kubeconfig

$ # 设置上下文参数
$ kubectl config set-context default \
  --cluster=kubernetes \
  --user=dashboard_user \
  --kubeconfig=dashboard.kubeconfig

$ # 设置默认上下文
$ kubectl config use-context default --kubeconfig=dashboard.kubeconfig
```

用生成的 dashboard.kubeconfig  登录 Dashboard。

![images/dashboard.png](images/dashboard.png)

由于缺少 Heapster 插件，当前 dashboard 不能展示 Pod、Nodes 的 CPU、内存等统计数据和图表；

## 参考
https://github.com/kubernetes/dashboard/wiki/Access-control
https://github.com/kubernetes/dashboard/issues/2558
https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/
