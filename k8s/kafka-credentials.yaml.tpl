apiVersion: v1
kind: Secret
metadata:
  name: ${secret_name}
  namespace: sentry
type: Opaque
stringData:
  mechanism: "${mechanism}"
  username: "${username}"
  password: "${password}"
