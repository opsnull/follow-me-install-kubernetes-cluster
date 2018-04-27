csr_file=/root/kube-proxy-csr.json
cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
      -ca-key=/etc/kubernetes/ssl/ca-key.pem \
      -config=/etc/kubernetes/ssl/ca-config.json \
      -profile=kubernetes ${csr_file} | cfssljson -bare kube-proxy
mkdir -p /etc/kubernetes/ssl
mv kube-proxy*.pem /etc/kubernetes/ssl/
