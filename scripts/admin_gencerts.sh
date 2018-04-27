csr_file=/home/vagrant/admin-csr.json
cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
      -ca-key=/etc/kubernetes/ssl/ca-key.pem \
      -config=/etc/kubernetes/ssl/ca-config.json \
      -profile=kubernetes ${csr_file} | cfssljson -bare admin

mkdir -p /etc/kubernetes/ssl
mv admin*.pem /etc/kubernetes/ssl

