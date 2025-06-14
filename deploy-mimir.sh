#!/bin/bash

# Usage:
# ./install-mimir.sh <namespace> <storage_account_name> <storage_account_key> <container_name>

set -e

NAMESPACE=$1
STORAGE_ACCOUNT_NAME=$2
STORAGE_ACCOUNT_KEY=$3
CONTAINER_NAME=$4

# Create namespace if it doesn't exist
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Create Kubernetes secret for Azure credentials
kubectl create secret generic mimir-azure-secret \
  --from-literal=AZURE_STORAGE_ACCOUNT=""$STORAGE_ACCOUNT_NAME"" \
  --from-literal=AZURE_STORAGE_KEY=""$STORAGE_ACCOUNT_KEY"" \
  -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Create a temporary values.yaml file


cat <<EOF > mimir-values.yaml
mimir:
  structuredConfig:
    common:
      storage:
        backend: azure
    blocks_storage:
      backend: azure
      tsdb:
        dir: /data/tsdb
      bucket_store:
        sync_dir: /data/tsdb-sync
      azure:
        account_name: "$STORAGE_ACCOUNT_NAME"
        account_key: "$STORAGE_ACCOUNT_KEY"
        container_name: mimir-blocks
        endpoint_suffix: blob.core.windows.net
    alertmanager_storage:
      backend: azure
      azure:
        account_name: "$STORAGE_ACCOUNT_NAME"
        account_key: "$STORAGE_ACCOUNT_KEY"
        container_name: mimir-alertmanager
        endpoint_suffix: blob.core.windows.net
    ruler_storage:
      backend: azure
      azure:
        account_name: "$STORAGE_ACCOUNT_NAME"
        account_key: "$STORAGE_ACCOUNT_KEY"
        container_name: mimir-ruler
        endpoint_suffix: blob.core.windows.net
    usage_stats:
      enabled: false

ingester:
  zoneAwareReplication:
    enabled: true
    zoneSpread:
      zones:
        - westus2-1
        - westus2-2
        - westus2-3
    zoneConfigTemplate:
      persistentVolume:
        enabled: true
        size: 10Gi  # Adjust size as needed
        storageClass: default # Use your StorageClass name
      tolerations:
        - key: "nodepool"
          operator: "Equal"
          value: "monitoring"
          effect: "NoSchedule"
      nodeSelector:
        agentpool: monitoring
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: "topology.kubernetes.io/zone"
          whenUnsatisfiable: "ScheduleAnyway"
          labelSelector:
            matchLabels:
              app.kubernetes.io/component: ingester


compactor:
  persistentVolume:
    enabled: false
    storageClass: jtest
  extraVolumes:
    - name: data
      emptyDir: {}
  extraVolumeMounts:
    - name: data
      mountPath: /data
  tolerations:
    - key: "nodepool"
      operator: "Equal"
      value: "monitoring"
      effect: "NoSchedule"
  nodeSelector:
    agentpool: monitoring

store_gateway:
  persistentVolume:
    enabled: false
    storageClass: jtest
  pod:
    extraVolumes:
      - name: tsdb-sync
        emptyDir: {}
    extraVolumeMounts:
      - name: tsdb-sync
        mountPath: /data/tsdb-sync
  zoneAwareReplication:
    enabled: true
    zoneAffinityEnabled: true
    zoneSpread:
      zones:
        - westus2-1
        - westus2-2
        - westus2-3
    zoneConfigTemplate:
      persistentVolume:
        enabled: false
        storageClass: jtest
      pod:
        extraVolumes:
          - name: tsdb-sync
            emptyDir: {}
        extraVolumeMounts:
          - name: tsdb-sync
            mountPath: /data/tsdb-sync

query_frontend:
  enabled: true

alertmanager:
  enabled: false

ruler:
  enabled: false

overrides_exporter:
  enabled: false

query_scheduler:
  enabled: false

minio:
  enabled: false
EOF



# Add Helm repo and upgrade/install Mimir
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install mimir grafana/mimir-distributed \
  -n "$NAMESPACE" \
  -f mimir-values.yaml
