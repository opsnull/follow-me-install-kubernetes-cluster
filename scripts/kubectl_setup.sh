wget https://dl.k8s.io/v1.6.2/kubernetes-client-linux-amd64.tar.gz
tar -xzvf kubernetes-client-linux-amd64.tar.gz
sudo cp kubernetes/client/bin/kube* /root/local/bin/
chmod a+x /root/local/bin/kube*
export PATH=/root/local/bin:$PATH
