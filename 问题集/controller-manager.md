1. kube-controller-manager 当前**必须**使用 --kubeconfig 参数指定 kube-apiserver 的地址、CA 证书和链接 kube-apiserver 使用的证书、私钥文件，不再支持使用 --tls-ca-file 参数。

--master 会覆盖 --kubeconfig 中指定的地址，但是 CA 证书、Client 证书还需要由 --kubeconfig 提供，否则 kube-controller-manager 启动时出错，原因是没有 CA 对 kube-apiserver 提供的证书进行验证：

[k8s@kube-node1 system]$ /opt/k8s/bin/kube-controller-manager \
    --bind-address=127.0.0.1   --port=0   --secure-port=10252 --master="https://172.27.129.105:6443" \
    --service-cluster-ip-range=10.254.0.0/16   --cluster-name=kubernetes   --cluster-signing-cert-file=/etc/kubernetes/cert/ca.pem \
    --cluster-signing-key-file=/etc/kubernetes/cert/ca-key.pem   --service-account-private-key-file=/etc/kubernetes/cert/ca-key.pem \
    --root-ca-file=/etc/kubernetes/cert/ca.pem   --leader-elect=true   --feature-gates=RotateKubeletServerCertificate=true   \
    --controllers=*,bootstrapsigner,tokencleaner   --horizontal-pod-autoscaler-use-rest-clients=true   --horizontal-pod-autoscaler-sync-period=10s \
    --tls-ca-file=/etc/kubernetes/cert/ca.pem --tls-cert-file=/etc/kubernetes/cert/kube-controller-manager.pem   \
    --tls-private-key-file=/etc/kubernetes/cert/kube-controller-manager-key.pem   --v=2

Jun 12 14:01:31 kube-node1 kube-controller-manager[24827]: Flag --tls-ca-file has been deprecated, This flag has no effect.
Jun 12 14:01:31 kube-node1 systemd[1]: Starting Kubernetes Controller Manager...
I0612 14:16:12.058255   26155 feature_gate.go:190] feature gates: map[RotateKubeletServerCertificate:true]
...
I0612 14:16:12.062266   26155 serve.go:96] Serving securely on 127.0.0.1:10252
I0612 14:16:12.062451   26155 leaderelection.go:175] attempting to acquire leader lease  kube-system/kube-controller-manager...
E0612 14:16:12.106287   26155 leaderelection.go:224] error retrieving resource lock kube-system/kube-controller-manager: Get https://172.27.129.105:6443/api/v1/namespaces/kube-system/endpoints/kube-controller-manager: x509: certificate signed by unknown authority

+ `--cluster-cidr`、`--allocate-node-cidrs` 是在启动 cloud provider 时才需要配置的参数，这里不做配置；
+ 不对 https /metrics 请求的 client 做证书验证；
+ 使用 --secure-port 时 --port 参数必须为 0，否则启动时提供端口被占用； 