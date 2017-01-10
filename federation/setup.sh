#!/bin/sh

gcloud container clusters create gce-us-east1 --zone=us-east1-b --num-nodes=1 --scopes "cloud-platform,storage-ro,logging-write,monitoring-write,service-control,service-management,https://www.googleapis.com/auth/ndev.clouddns.readwrite"
gcloud container clusters create gce-us-central1 --zone=us-central1-b --num-nodes=1 --scopes "cloud-platform,storage-ro,logging-write,monitoring-write,service-control,service-management,https://www.googleapis.com/auth/ndev.clouddns.readwrite"

export GCP_PROJECT=$(gcloud config list --format='value(core.project)')

kubectl config use-context "gke_${GCP_PROJECT}_us-central1-b_gce-us-central1"
US_CENTRAL_SERVER_ADDRESS=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

mkdir -p clusters

cat > clusters/gce-us-central1.yaml <<EOF
apiVersion: federation/v1beta1
kind: Cluster
metadata:
  name: gce-us-central1
spec:
  serverAddressByClientCIDRs:
    - clientCIDR: "0.0.0.0/0"
      serverAddress: "${US_CENTRAL_SERVER_ADDRESS}"
  secretRef:
    name: gce-us-central1
EOF

mkdir -p kubeconfigs/gce-us-central1

kubectl config view --flatten --minify > kubeconfigs/gce-us-central1/kubeconfig

kubectl config use-context "gke_${GCP_PROJECT}_us-east1-b_gce-us-east1"
US_EAST_SERVER_ADDRESS=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

cat > clusters/gce-us-east1.yaml <<EOF
apiVersion: federation/v1beta1
kind: Cluster
metadata:
  name: gce-us-east1
spec:
  serverAddressByClientCIDRs:
    - clientCIDR: "0.0.0.0/0"
      serverAddress: "${US_EAST_SERVER_ADDRESS}"
  secretRef:
    name: gce-us-east1
EOF

mkdir -p kubeconfigs/gce-us-east1

kubectl config view --flatten --minify > kubeconfigs/gce-us-east1/kubeconfig

gcloud dns managed-zones create meygam \
  --description "Kubernetes federation testing" \
  --dns-name meygam.io

export GCP_PROJECT=$(gcloud config list --format='value(core.project)')

kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" \
  apply -f ns/federation.yaml

kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" \
  apply -f services/federation-apiserver.yaml

kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" \
  --namespace=federation \
  create secret generic federation-apiserver-secrets --from-file=known-tokens.csv


kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" \
  --namespace=federation \
  create -f pvc/federation-apiserver-etcd.yaml

sleep 300

FEDERATED_API_SERVER_ADDRESS=$(kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" \
  --namespace=federation \
  get services federation-apiserver \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

sed -i "" "s|ADVERTISE_ADDRESS|${FEDERATED_API_SERVER_ADDRESS}|g" deployments/federation-apiserver.yaml

kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" \
  --namespace=federation \
  apply -f deployments/federation-apiserver.yaml

kubectl config set-cluster federation-cluster \
  --server=https://${FEDERATED_API_SERVER_ADDRESS} \
  --insecure-skip-tls-verify=true

FEDERATION_CLUSTER_TOKEN=$(cut -d"," -f1 known-tokens.csv)

kubectl config set-credentials federation-cluster \
  --token=${FEDERATION_CLUSTER_TOKEN}

kubectl config set-context federation-cluster \
  --cluster=federation-cluster \
  --user=federation-cluster

kubectl config use-context federation-cluster

mkdir -p kubeconfigs/federation-apiserver

kubectl  config view --flatten --minify > kubeconfigs/federation-apiserver/kubeconfig

kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" \
  --namespace=federation \
  create secret generic federation-apiserver-kubeconfig \
  --from-file=kubeconfigs/federation-apiserver/kubeconfig

kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" \
  --namespace=federation \
  create -f deployments/federation-controller-manager.yaml

kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" \
  --namespace=federation \
  create secret generic gce-us-central1 \
  --from-file=kubeconfigs/gce-us-central1/kubeconfig

kubectl --context=federation-cluster \
  apply -f clusters/gce-us-central1.yaml

kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" \
  --namespace=federation \
  create secret generic gce-us-east1 \
  --from-file=kubeconfigs/gce-us-east1/kubeconfig

kubectl --context=federation-cluster \
  apply -f clusters/gce-us-east1.yaml

sleep 120

kubectl --context=federation-cluster get clusters

kubectl --context=federation-cluster create -f rs/nginx.yaml
kubectl --context=federation-cluster create -f services/nginx.yaml
