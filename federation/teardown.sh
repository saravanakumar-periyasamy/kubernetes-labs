gcloud container clusters delete gce-us-central1 --zone=us-central1-b
gcloud container clusters delete gce-us-east1 --zone=us-east1-b

rm clusters/*.yaml
rm -rf kubeconfigs/*

gcloud dns managed-zones delete meygam
