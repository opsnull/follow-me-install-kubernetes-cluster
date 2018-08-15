[root@m7-autocv-gpu02 ~]# sudo yum --enablerepo=elrepo-kernel install -y kernel-lt-headers kernel-lt-devel # 必须先要安装这两个包，否则不能正确生成 nvidia.ko
[root@m7-autocv-gpu03 ~]# mv /etc/yum.repos.d/elrepo.repo{,.bak} # 需要移除 elrepo，否则后面安装 cuda 的时候提示冲突：nvidia-x11-drv-340xx conflicts with 1:xorg-x11-drv-nvidia-396.37-1.el7.x86_64

[root@m7-autocv-gpu03 ~]# ls /tmp/cuda-repo-rhel7-9-2-*
/tmp/cuda-repo-rhel7-9-2-148-local-patch-1-1.0-1.x86_64.rpm  /tmp/cuda-repo-rhel7-9-2-local-9.2.148-1.x86_64.rpm

[root@m7-autocv-gpu02 ~]# yum install cuda

[root@m7-autocv-gpu02 ~]# nvidia-
nvidia-bug-report.sh     nvidia-cuda-mps-control  nvidia-cuda-mps-server   nvidia-debugdump         nvidia-modprobe          nvidia-persistenced      nvidia-settings          nvidia-smi               nvidia-xconfig

[root@m7-autocv-gpu02 ~]# nvidia-modprobe
[root@m7-autocv-gpu02 ~]# nvidia-smi
Tue Aug 14 20:55:18 2018
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 396.37                 Driver Version: 396.37                    |
|-------------------------------+----------------------+----------------------+
| GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
|===============================+======================+======================|
|   0  GeForce GTX 108...  Off  | 00000000:02:00.0 Off |                  N/A |
| 23%   33C    P0    51W / 250W |      0MiB / 11178MiB |      0%      Default |
+-------------------------------+----------------------+----------------------+

+-----------------------------------------------------------------------------+
| Processes:                                                       GPU Memory |
|  GPU       PID   Type   Process name                             Usage      |
|=============================================================================|
|  No running processes found                                                 |
+-----------------------------------------------------------------------------+
[root@m7-autocv-gpu02 ~]#