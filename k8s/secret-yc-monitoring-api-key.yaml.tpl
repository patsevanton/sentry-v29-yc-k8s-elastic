apiVersion: v1
kind: Secret
metadata:
  name: yc-monitoring-api-key
  namespace: vmks
type: Opaque
stringData:
  bearer: "${monitoring_api_key}"
