csr_file=/root/kubernetes-csr.json
cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
      -ca-key=/etc/kubernetes/ssl/ca-key.pem \
      -config=/etc/kubernetes/ssl/ca-config.json \
      -profile=kubernetes ${csr_file} | cfssljson -bare kubernetes

mkdir -p /etc/kubernetes/ssl
mv kubernetes*.pem /etc/kubernetes/ssl
