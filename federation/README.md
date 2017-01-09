# Instructions to setup federation cluster

> Note: This instructions are inspired from https://github.com/kelseyhightower/kubernetes-cluster-federation. Modified it to have smaller setup cost, particularly reduced number of clusters to 2 and number of nodes in each cluster to 1.

gcloud container clusters create gce-us-east1 --zone=us-east1-b --num-nodes=1
gcloud container clusters create gce-us-central1 --zone=us-central1-b --num-nodes=1

export GCP_PROJECT=$(gcloud config list --format='value(core.project)')
