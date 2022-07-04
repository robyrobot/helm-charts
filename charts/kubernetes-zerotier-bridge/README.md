# Kubernetes Zerotier bridge 

# Why this fork
This is a fork of: https://github.com/leunamnauj/kubernetes-zerotier-bridge. 

### *TL;DR*
A Zerotier gateway to access your non-public k8s services thru ZT subnet 

### Kubernetes

## Helm chart to deploy a DaemonSet
`helm repo add kubernetes-zerotier-bridge https://robyrobot.github.io/helm-charts`

`helm repo update`

`helm install --name kubernetes-zerotier-bridge kubernetes-zerotier-bridge/kubernetes-zerotier-bridge`

**Note:** You are able to configure persistence setting `persistentVolume.enabled=true` and further storage parameters as needed.

## Single Deployment
Since this docker image expects the subnetIDs as an env variable you need to use something like this
```
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: zerotier-networks
data:
  NETWORK_IDS: << your subnetid >>
  ZTAUTHTOKEN: << your token >>
  AUTOJOIN: true
  ZTHOSTNAME: << desired hostname>>
---
apiVersion: v1
kind: Pod
metadata:
  name: kubernetes-zerotier-bridge
spec:
  containers:
    - name: ubernetes-zerotier-bridge
      image: << your registry >>
      env:
      - name: NETWORK_IDS
        valueFrom:
          configMapKeyRef:
            name: zerotier-networks
            key: NETWORK_IDS 
      - name: ZTHOSTNAME
        valueFrom:
          configMapKeyRef:
            name: zerotier-networks
            key: ZTHOSTNAME 
      - name: ZTAUTHTOKEN
        valueFrom:
          configMapKeyRef:
            name: zerotier-networks
            key: ZTAUTHTOKEN 
      - name: AUTOJOIN
        valueFrom:
          configMapKeyRef:
            name: zerotier-networks
            key: AUTOJOIN 
      securityContext:
          privileged: true
          capabilities:
            add:
            - NET_ADMIN
            - SYS_ADMIN
            - CAP_NET_ADMIN
        volumeMounts:
        - name: dev-net-tun
          mountPath: /dev/net/tun

```
**Important:** Be aware of `securityContext` and `dev-net-tun` volume

## Zerotier level config
In order to route traffic to this POD have to add the proper rule on ZT Managed Routes section, to accomplish that you have to know the ZT address assigned to the pod and your Service and/or PODs subnet.


## Inspired on

* https://github.com/henrist/zerotier-one-docker
* https://github.com/crocandr/docker-zerotier
