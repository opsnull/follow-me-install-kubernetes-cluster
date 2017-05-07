<!-- toc -->

tags: EFK, fluentd, elasticsearch, kibana

# 部署 EFK 插件

官方文件目录：`kubernetes/cluster/addons/fluentd-elasticsearch`

``` bash
$ ls *.yaml
es-controller.yaml es-rbac.yaml es-service.yaml  fluentd-es-ds.yaml  kibana-controller.yaml  kibana-service.yaml fluentd-es-rbac.yaml
```

+ 新加了 `es-rbac.yaml` 和 `fluentd-es-rbac.yaml` 文件，定义了 elasticsearch 和 fluentd 使用的 Role 和 RoleBinding；

已经修改好的 yaml 文件见：[EFK](https://github.com/opsnull/follow-me-install-kubernetes-cluster/blob/master/manifests/EFK)。


## 配置 es-controller.yaml

``` bash
$ diff es-controller.yaml.orig es-controller.yaml
22a23
>       serviceAccountName: elasticsearch
24c25
<       - image: gcr.io/google_containers/elasticsearch:v2.4.1-2
---
>       - image: onlyerich/elasticsearch:v2.4.1-2
```

## 配置 es-service.yaml

无需配置；

## 配置 fluentd-es-ds.yaml

``` bash
$ diff fluentd-es-ds.yaml.orig fluentd-es-ds.yaml
23a24
>       serviceAccountName: fluentd
26c27
<         image: gcr.io/google_containers/fluentd-elasticsearch:1.22
---
>         image: onlyerich/fluentd-elasticsearch:1.22
```

## 配置 kibana-controller.yaml

``` bash
$ diff kibana-controller.yaml.orig kibana-controller.yaml
22c22
<         image: gcr.io/google_containers/kibana:v4.6.1-1
---
>         image: onlyerich/kibana:v4.6.1-1
```

## 给 Node 设置标签

DaemonSet `fluentd-es-v1.22` 只会调度到设置了标签 `beta.kubernetes.io/fluentd-ds-ready=true` 的 Node，需要在期望运行 fluentd 的 Node 上设置该标签；

``` bash
$ kubectl get nodes
NAME        STATUS    AGE       VERSION
10.64.3.7   Ready     1d        v1.6.2

$ kubectl label nodes 10.64.3.7 beta.kubernetes.io/fluentd-ds-ready=true
node "10.64.3.7" labeled
```

## 执行定义文件

``` bash
$ pwd
/root/kubernetes/cluster/addons/fluentd-elasticsearch
$ ls *.yaml
es-controller.yaml es-rbac.yaml es-service.yaml  fluentd-es-ds.yaml  kibana-controller.yaml  kibana-service.yaml fluentd-es-rbac.yaml
$ kubectl create -f .
$
```

## 检查执行结果

``` bash
$ kubectl get deployment -n kube-system|grep kibana
kibana-logging         1         1         1            1           2m

$ kubectl get pods -n kube-system|grep -E 'elasticsearch|fluentd|kibana'
elasticsearch-logging-v1-kwc9w          1/1       Running   0          4m
elasticsearch-logging-v1-ws9mk          1/1       Running   0          4m
fluentd-es-v1.22-g76x0                  1/1       Running   0          4m
kibana-logging-324921636-ph7sn          1/1       Running   0          4m

$ kubectl get service  -n kube-system|grep -E 'elasticsearch|kibana'
elasticsearch-logging   10.254.128.156   <none>        9200/TCP        3m
kibana-logging          10.254.88.109    <none>        5601/TCP        3m
```

kibana Pod 第一次启动时会用**较长时间(10-20分钟)**来优化和 Cache 状态页面，可以 tailf 该 Pod 的日志观察进度：

``` bash
$ kubectl logs kibana-logging-324921636-ph7sn -n kube-system -f
ELASTICSEARCH_URL=http://elasticsearch-logging:9200
server.basePath: /api/v1/proxy/namespaces/kube-system/services/kibana-logging
{"type":"log","@timestamp":"2017-04-08T09:30:30Z","tags":["info","optimize"],"pid":7,"message":"Optimizing and caching bundles for kibana and statusPage. This may take a few minutes"}
{"type":"log","@timestamp":"2017-04-08T09:44:01Z","tags":["info","optimize"],"pid":7,"message":"Optimization of bundles for kibana and statusPage complete in 811.00 seconds"}
{"type":"log","@timestamp":"2017-04-08T09:44:02Z","tags":["status","plugin:kibana@1.0.0","info"],"pid":7,"state":"green","message":"Status changed from uninitialized to green - Ready","prevState":"uninitialized","prevMsg":"uninitialized"}
```

## 访问 kibana

1. 通过 kube-apiserver 访问：

    获取 monitoring-grafana 服务 URL

    ``` bash
    $ kubectl cluster-info
    Kubernetes master is running at https://10.64.3.7:6443
    Elasticsearch is running at https://10.64.3.7:6443/api/v1/proxy/namespaces/kube-system/services/elasticsearch-logging
    Heapster is running at https://10.64.3.7:6443/api/v1/proxy/namespaces/kube-system/services/heapster
    Kibana is running at https://10.64.3.7:6443/api/v1/proxy/namespaces/kube-system/services/kibana-logging
    KubeDNS is running at https://10.64.3.7:6443/api/v1/proxy/namespaces/kube-system/services/kube-dns
    kubernetes-dashboard is running at https://10.64.3.7:6443/api/v1/proxy/namespaces/kube-system/services/kubernetes-dashboard
    monitoring-grafana is running at https://10.64.3.7:6443/api/v1/proxy/namespaces/kube-system/services/monitoring-grafana
    monitoring-influxdb is running at https://10.64.3.7:6443/api/v1/proxy/namespaces/kube-system/services/monitoring-influxdb
    ```

    由于 kube-apiserver 开启了 RBAC 授权，而浏览器访问 kube-apiserver 的时候使用的是匿名证书，所以访问安全端口会导致授权失败。这里需要使用**非安全**端口访问 kube-apiserver：

    浏览器访问 URL： `http://10.64.3.7:8080/api/v1/proxy/namespaces/kube-system/services/kibana-logging`

1. 通过 kubectl proxy 访问：

    创建代理

    ``` bash
    $ kubectl proxy --address='10.64.3.7' --port=8086 --accept-hosts='^*$'
    Starting to serve on 10.64.3.7:8086
    ```

    浏览器访问 URL：`http://10.64.3.7:8086/api/v1/proxy/namespaces/kube-system/services/kibana-logging`

在 Settings -> Indices 页面创建一个 index（相当于 mysql 中的一个 database），选中 `Index contains time-based events`，使用默认的 `logstash-*` pattern，点击 `Create` ;

![es-setting](./images/es-setting.png)

创建Index后，稍等几分钟就可以在 `Discover` 菜单下看到 ElasticSearch logging 中汇聚的日志；

![es-home](./images/es-home.png)