etcd_csr_file=/home/vagrant/etcd-csr.json
cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
      -ca-key=/etc/kubernetes/ssl/ca-key.pem \
      -config=/etc/kubernetes/ssl/ca-config.json \
      -profile=kubernetes ${etcd_csr_file} | cfssljson -bare etcd

mkdir -p /etc/etcd/ssl
mv etcd*.pem /etc/etcd/ssl
# rm etcd.csr  etcd-csr.json
