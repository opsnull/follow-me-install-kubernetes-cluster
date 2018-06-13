# 访问 etcd 时提示 context deadline exceeded

[k8s@kube-node1 ssl]$ ETCDCTL_API=3 /opt/k8s/bin/etcdctl --endpoints=https://172.27.129.105:2379 endpoint health
https://172.27.129.105:2379 is unhealthy: failed to connect: context deadline exceeded
Error: unhealthy cluster

etcd 的日志出现：

Jun 11 14:11:02 kube-node1 etcd[10736]: finished scheduled compaction at 54009 (took 687.526µs)
Jun 11 14:13:10 kube-node1 etcd[10736]: rejected connection from "172.27.129.105:49968" (error "remote error: tls: bad certificate", ServerName "")

原因：etcd 启用了加密模式，但是 etcdctl 为指定证书和私钥文件；
解决：指定证书和私钥：
[k8s@kube-node1 ssl]$ ETCDCTL_API=3 /opt/k8s/bin/etcdctl --endpoints=https://172.27.129.105:2379 --cacert=/etc/kubernetes/ssl/ca.pem --cert=/etc/etcd/ssl/etcd.pem --key=/etc/etcd/ssl/etcd-key.pem endpoint health
https://172.27.129.105:2379 is healthy: successfully committed proposal: took = 1.941265ms

+ --cacert：验证 etcd server 的证书；
+  --cert、--key：提供给 etcd server 的 client 证书；

# etcd 生成环境推荐配置

1. message 最大字节数；
1. 版本次数；