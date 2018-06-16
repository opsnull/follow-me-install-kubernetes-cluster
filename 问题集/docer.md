# docker mount default serviceaccount token 失败，提示超时
错误日志：The f5112c1", APIVersion:"v1", ResourceVersion:"771", FieldPath:""}): type: 'Warning' reason: 'FailedMount' Unable to mount volumes for pod "cli-with-token_test(0 ba7ffca-46fc-11e6-af1a-0e6a9f5112c1)": timeout expired waiting for volumes to attach/mount for pod "cli-with-token"/"test". list of unattached/unmounted volum es=[default-token-2uhpl] 

原因：如果某些 POD 共享一个 volume，K8S 就会串行创建它们。而 POD 默认都会挂载一个 default ServiceAccount，所以串行了，靠后 mount 的可能超时。给这些 POD 都创建和挂载自己的 ServiceAccount 就没这个问题，并行创建。
https://github.com/kubernetes/kubernetes/issues/28616#issuecomment-231249817

# 修改系统时间

另一个问题，k8s 集群的时间如果要改，就需要重启或者重新部署，因为容器创建时间发生异常，docker已经无法正常运行