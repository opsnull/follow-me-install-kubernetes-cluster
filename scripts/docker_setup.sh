wget https://get.docker.com/builds/Linux/x86_64/docker-17.04.0-ce.tgz
tar -xvf docker-17.04.0-ce.tgz
cp docker/docker* /root/local/bin
cp docker/completion/bash/docker /etc/bash_completion.d/
