apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: kafka-trigger-auth
  namespace: sentry
spec:
  secretTargetRef:
    - parameter: password
      name: ${kafka_credentials_secret_name}
      key: password
    - parameter: username
      name: ${kafka_credentials_secret_name}
      key: username
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: taskworker-ingest
  namespace: sentry
spec:
  scaleTargetRef:
    name: sentry-taskworker-ingest
  minReplicaCount: 1
  maxReplicaCount: 8
  pollingInterval: 30
  cooldownPeriod: 600
  triggers:
    - type: kafka
      metadata:
        bootstrapServers: >-
          ${kafka_bootstrap_servers}
        consumerGroup: taskworker-ingest
        topic: taskworker-ingest
        lagThreshold: "1000"
        activationLagThreshold: "100"
        offsetResetPolicy: latest
        sasl: "scram_sha512"
        tls: "disable"
      authenticationRef:
        name: kafka-trigger-auth
