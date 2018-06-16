E0616 08:38:05.007054       1 manager.go:101] Error in scraping containers from kubelet:172.27.129.111:10250: failed to get all container stats from Kubelet URL "https://172.27.129.111:10250/stats/container/": request failed - "403 Forbidden", response: "Forbidden (user=system:serviceaccount:kube-system:heapster, verb=create, resource=nodes, subresource=stats)"

原因：serviceaccount kube-system:heapster 没有访问 kubelet API 的权限；
解决办法：授予权限；

$ diff heapster-rbac.yaml.orig heapster-rbac.yaml
12a13,26
> ---
> kind: ClusterRoleBinding
> apiVersion: rbac.authorization.k8s.io/v1beta1
> metadata:
>   name: heapster-kubelet-api
> roleRef:
>   apiGroup: rbac.authorization.k8s.io
>   kind: ClusterRole
>   name: system:kubelet-api-admin
> subjects:
> - kind: ServiceAccount
>   name: heapster
>   namespace: kube-system