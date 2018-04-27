csr_file=/root/flanneld-csr.json
cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
      -ca-key=/etc/kubernetes/ssl/ca-key.pem \
      -config=/etc/kubernetes/ssl/ca-config.json \
      -profile=kubernetes ${csr_file} | cfssljson -bare flanneld

mkdir -p /etc/flanneld/ssl
mv flanneld*.pem /etc/flanneld/ssl
# rm etcd.csr  etcd-csr.json
