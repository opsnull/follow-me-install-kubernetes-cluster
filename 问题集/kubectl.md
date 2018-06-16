# kublet 开启认证和授权后，kubectl exec 提示 unauthorized

[k8s@kube-node1 k8s]$ kubectl exec -it nginx-ds-5rmws -- sh
error: unable to upgrade connection: Unauthorized

kubelet 的日志：
Jun 16 14:35:02 kube-node2 kubelet[2490]: I0616 14:35:02.961284    2490 server.go:796] POST /exec/default/nginx-ds-5rmws/my-nginx?command=sh&input=1&output=1&tty=1: (120.887µs) 401
Jun 16 14:35:02 kube-node2 kubelet[2490]: goroutine 60539 [running]:
Jun 16 14:35:02 kube-node2 kubelet[2490]: k8s.io/kubernetes/vendor/k8s.io/apiserver/pkg/server/httplog.(*respLogger).recordStatus(0xc4218d2460, 0x191)
Jun 16 14:35:02 kube-node2 kubelet[2490]: /workspace/anago-v1.10.4-beta.0.68+5ca598b4ba5abb/src/k8s.io/kubernetes/_output/dockerized/go/src/k8s.io/kubernetes/vendor/k8s.io/apiserver/pkg/server/httplog/httplog.go:207 +0xdd

原因：kube-apiserver 没有通过 --kubelet-client-certificate、--kubelet-client-key 指定访问 kubelet https 的证书；

error: unable to upgrade connection: Unauthorized
[k8s@kube-node1 k8s]$ kubectl exec -it nginx-ds-5rmws -- sh
error: unable to upgrade connection: Forbidden (user=kubernetes, verb=create, resource=nodes, subresource=proxy)

## kublet 开启认证和授权后，kubectl exec 提示 Forbidden

[k8s@kube-node1 k8s]$ kubectl exec -it nginx-ds-5rmws -- sh
error: unable to upgrade connection: Forbidden (user=kubernetes, verb=create, resource=nodes, subresource=proxy)

原因：kube-apiserver 通过 --kubelet-client-certificate、--kubelet-client-key 配置的证书没有调用 kubelet API 的权限:

verb=*, resource=nodes, subresource=proxy
verb=*, resource=nodes, subresource=stats
verb=*, resource=nodes, subresource=log
verb=*, resource=nodes, subresource=spec
verb=*, resource=nodes, subresource=metrics

解决办法：授予 kube-apiserver 使用的 kubelet-client 证书访问 kubelet-api-admin 的权限

``` bash
$ kubectl create clusterrolebinding kube-apiserver:kubelet-apis --clusterrole=system:kubelet-api-admin --user kubernetes
```

参考：https://kubernetes.io/docs/admin/kubelet-authentication-authorization/#kubelet-authorization