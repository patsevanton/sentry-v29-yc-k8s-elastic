# Container Registry (yc container registry)

## Registry Commands

```
yc container registry list
yc container registry get <NAME|ID>
yc container registry create --name NAME
yc container registry update <NAME|ID> [flags]
yc container registry delete <NAME|ID>
yc container registry configure-docker
```

## Repository & Image Commands

```
yc container repository list --registry-name NAME
yc container image list --repository-name <REGISTRY-NAME/REPO-NAME>
yc container image delete <IMAGE-ID>
yc container image scan <IMAGE-ID>
```

## Docker Auth

```bash
# Configure docker to use yc for auth
yc container registry configure-docker

# Or manually
echo $(yc iam create-token) | docker login --username iam --password-stdin cr.yandex
```

## Push/Pull Workflow

```bash
# 1. Create registry
yc container registry create --name my-registry
REGISTRY_ID=$(yc container registry get --name my-registry --format json | jq -r .id)

# 2. Configure docker auth
yc container registry configure-docker

# 3. Build and push
docker build -t cr.yandex/$REGISTRY_ID/my-app:v1 .
docker push cr.yandex/$REGISTRY_ID/my-app:v1

# 4. Pull
docker pull cr.yandex/$REGISTRY_ID/my-app:v1
```

## Lifecycle Policies

```bash
yc container repository lifecycle-policy list --repository-name <REGISTRY/REPO>
yc container repository lifecycle-policy create \
  --repository-name <REGISTRY/REPO> \
  --name cleanup \
  --active \
  --rule "description=Remove untagged older than 48h,untagged=true,expire-period=48h"
```
