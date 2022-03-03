## Overview
This repository contains my helm-chart. Feel free to use it ;)

## Usage

[Helm](https://helm.sh) must be installed to use the charts.  Please refer to
Helm's [documentation](https://helm.sh/docs) to get started.

Once Helm has been set up correctly, add the repo as follows:

  helm repo add robyrobot https://robyrobot.github.io/helm-charts

If you had already added this repo earlier, run `helm repo update` to retrieve
the latest versions of the packages.  
You can then run `helm search repo robyrobot` to see the charts.

For example if you wish to install the zerotier-bridge chart:

    helm install my-zerotier-bridge robyrobot/zerotier-bridge

To uninstall the chart:

    helm uninstall my-zerotier-bridge

NOTE: remember to create a value.yaml replacing zerotier config value with the correct ones 
