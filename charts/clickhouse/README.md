# clickhouse

A Helm chart for deploying ClickHouse with optional ClickHouse Keeper

![Version: 0.2.5](https://img.shields.io/badge/Version-0.2.5-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 25.9.3-alpine](https://img.shields.io/badge/AppVersion-25.9.3--alpine-informational?style=flat-square)

## Features

- **Distributed Architecture**: Configurable number of shards and replicas for scalability and high availability
- **Persistent Storage**: Support for local volumes and S3-compatible object storage integration
- **Security**: Authentication for ClickHouse, inter-server communication, and Keeper
- **ClickHouse Keeper**: Built-in coordination service as a ZooKeeper replacement
- **Customization**: Flexible configuration options and initialization scripts
- **Metrics**: Optional Prometheus metrics integration

## Storage Configuration

### Local Storage

By default, the chart uses PersistentVolumeClaims to store data. Storage class and size can be configured:

```yaml
clickhouse:
  persistentVolume:
    enabled: true
    storageClass: ""
    size: 20Gi
```

### S3 Storage

ClickHouse supports using S3-compatible object storage for data storage:

```yaml
clickhouse:
  # Set this to 's3' to use S3 storage as the default policy
  defaultStoragePolicy: s3
 
  storageConfiguration:
    enabled: true
    s3Endpoint: https://bucket-name.s3.region-name.amazonaws.com/path/
```

The S3 configuration assumes credentials are available through the pod's environment (instance profile, environment variables, etc.). For other authentication methods, customize the configTemplate:

```yaml
clickhouse:
  storageConfiguration:
    enabled: true
    s3Endpoint: https://bucket-name.s3.region-name.amazonaws.com/path/

    configTemplate: |
      disks:
        s3_disk:
          type: object_storage
          object_storage_type: s3
          metadata_type: local
          endpoint: {{ .Values.clickhouse.storageConfiguration.s3Endpoint }}
          # Use different auth method here - example for access/secret keys:
          access_key_id: ACCESS_KEY
          secret_access_key: SECRET_KEY
          metadata_path: /var/lib/clickhouse/disks/s3_disk/
        s3_cache:
          type: cache
          disk: s3_disk
          path: /var/lib/clickhouse/disks/s3_cache/
          max_size: 10Gi
      policies:
        s3:
          volumes:
            main:
              disk: s3_disk
```

## Authentication Options

### ClickHouse Authentication

Secure access to ClickHouse servers with username and password authentication.

```yaml
clickhouse:
  auth:
    enabled: true
    # Option 1: Chart-created secret
    createSecret: true
    username: "default"
    password: "secure-password"
   
    # Option 2: Existing secret
    createSecret: false
    secretName: "clickhouse-auth" # Must contain keys: username, password
```

### Interserver Authentication

Secure communication between ClickHouse nodes in a cluster.

```yaml
clickhouse:
  interserverCredentials:
    enabled: true
    # Option 1: Chart-created secret
    createSecret: true
    username: "interserver"
    password: "secure-password"
   
    # Option 2: Existing secret
    createSecret: false
    secretName: "clickhouse-interserver-auth" # Must contain keys: username, password
```

### Keeper Authentication

Control access to ClickHouse Keeper service for metadata management.

```yaml
keeper:
  auth:
    enabled: true
    # Option 1: Chart-created secret
    createSecret: true
    username: "keeper"
    password: "secure-password"
   
    # Option 2: Existing secret
    createSecret: false
    secretName: "clickhouse-keeper-auth"
    secretKey: "auth-string"  # Contains auth string in "username:password" format
```

> [!WARNING]
> After initial deployment, Keeper authentication credentials cannot be changed using Helm.
> Attempting to change these credentials will result in an error during Helm upgrade.
> To change credentials, you must do so manually using ZooKeeper tools.

## Configuration Options

Both ClickHouse and ClickHouse Keeper can be customized with additional configuration parameters.

### ClickHouse Custom Configuration

```yaml
clickhouse:
  customConfig:
    max_memory_usage: 10000000000
    max_concurrent_queries: 100
    log_queries_min_type: EXCEPTION_WHILE_PROCESSING
```

For more information about available ClickHouse Server settings, refer to the [ClickHouse Server Settings Documentation](https://clickhouse.com/docs/operations/server-configuration-parameters/settings).

### ClickHouse Keeper Custom Configuration

```yaml
keeper:
  customConfig:
    keeper_server:
      raft_settings:
        min_session_timeout_ms: 10000
        election_timeout_min: 1000
      coordination_settings:
        session_timeout_ms: 30000
```

For more information about available ClickHouse Keeper settings, refer to the [ClickHouse Keeper Documentation](https://clickhouse.com/docs/guides/sre/keeper/clickhouse-keeper).

> [!TIP]
> Existing ClickHouse XML configurations can be converted to YAML using [yq](https://github.com/mikefarah/yq):
>
> ```bash
> yq -oy '.' clickhouse_config.xml
> ```

## Deployment Example

```yaml
clickhouse:
  # Number of independent shards (data partitioning)
  shards: 1
  # Number of replicas per shard (high availability)
  replicasPerShard: 3

  # Authentication configuration
  auth:
    enabled: true
    createSecret: true
    username: "default"
    password: "secure-password"
    accessManagement: true

  # Secure inter-server communication
  interserverCredentials:
    enabled: true
    username: "interserver"
    password: "secure-interserver-password"

  # S3 storage configuration
  defaultStoragePolicy: "s3"
  storageConfiguration:
    enabled: true
    s3Endpoint: "https://bucket-name.s3.region-name.amazonaws.com/data/"

  # Local persistent storage for metadata and cache
  persistentVolume:
    enabled: true
    size: 20Gi

keeper:
  # Enable ClickHouse Keeper for cluster coordination
  enabled: true
  replicas: 3

  # Keeper authentication
  auth:
    enabled: true
    username: "keeper"
    password: "secure-keeper-password"

  # Persistent storage for Keeper
  persistentVolume:
    enabled: true
    size: 5Gi
```

## Values

### ClickHouse Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| clickhouse.affinity | object | `{}` | Custom affinity rules for ClickHouse pods - if specified, will override default pod anti-affinity |
| clickhouse.clusterName | string | `"default"` | Name of the ClickHouse cluster |
| clickhouse.customConfig | object | `{}` | Custom ClickHouse configuration. This will be merged with the default configuration. |
| clickhouse.database.name | string | `""` | Name of the default database to create during initialization |
| clickhouse.env | list | `[]` | Custom environment variables for ClickHouse containers |
| clickhouse.image.repository | string | `"clickhouse/clickhouse-server"` | ClickHouse server image repository |
| clickhouse.image.tag | string | `""` | ClickHouse server image tag (defaults to chart appVersion if empty) |
| clickhouse.initdb.alwaysRun | bool | `false` | Always run initdb scripts even if database already exists |
| clickhouse.initdb.existingSecret | string | `""` | Name of an existing secret containing initialization scripts |
| clickhouse.initdb.scripts | object | `{}` | Scripts to run during initialization |
| clickhouse.logLevel | string | `"information"` | Logging level for ClickHouse. Valid values: none, fatal, critical, error, warning, notice, information, debug, trace. |
| clickhouse.metrics.enabled | bool | `false` | Enable Prometheus metrics |
| clickhouse.podAntiAffinity.topologyKey | string | `"kubernetes.io/hostname"` | Topology key for pod anti-affinity |
| clickhouse.podAntiAffinity.type | string | `"soft"` | Pod anti-affinity type: can be "soft" or "hard" |
| clickhouse.podAntiAffinity.weight | int | `100` | Weight for soft pod anti-affinity (ignored if type is hard) |
| clickhouse.podDisruptionBudget.enabled | bool | `true` | Enable PodDisruptionBudget for ClickHouse |
| clickhouse.podDisruptionBudget.maxUnavailable | int | `1` | Maximum number of pods that can be unavailable |
| clickhouse.replicasPerShard | int | `1` | Number of replicas per shard for high availability. Each replica contains the same data as others in the shard. |
| clickhouse.securityContext | object | `{"fsGroup":101,"runAsGroup":101,"runAsUser":101}` | Security context for ClickHouse pods. UID 101 is the clickhouse user in the official Docker image. |
| clickhouse.serviceAccount.annotations | object | `{}` | Annotations to add to the service account |
| clickhouse.serviceAccount.create | bool | `true` | Create a service account for ClickHouse |
| clickhouse.serviceAccount.name | string | `""` | Name of the service account (if empty, generates based on fullname template) |
| clickhouse.shards | int | `1` | Number of shards in the ClickHouse cluster. Each shard contains a subset of the data and processes queries independently. |

### Authentication

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| clickhouse.auth.accessManagement | bool | `false` | Enable ClickHouse's access management system for creating/managing users via SQL |
| clickhouse.auth.createSecret | bool | `true` | Create a secret for credentials (if false, secretName must reference an existing secret) |
| clickhouse.auth.enabled | bool | `false` | Enable authentication for ClickHouse |
| clickhouse.auth.password | string | `""` | Password (used when createSecret is true) |
| clickhouse.auth.secretName | string | `""` | Name of the secret to create or use (auto-generated if empty) Existing secret must have keys: 'username' and 'password' |
| clickhouse.auth.skipUserSetup | bool | `false` | Set to true to skip automatic user setup, allowing the insecure 'default' user to be available. |
| clickhouse.auth.username | string | `"default"` | Username (used when createSecret is true) |
| clickhouse.interserverCredentials.createSecret | bool | `true` | Create a secret for credentials (if false, secretName must reference an existing secret) |
| clickhouse.interserverCredentials.enabled | bool | `false` | Enable authentication between ClickHouse servers |
| clickhouse.interserverCredentials.password | string | `""` | Password (used when createSecret is true) |
| clickhouse.interserverCredentials.secretName | string | `""` | Name of the secret to create or use (auto-generated if empty) Existing secret must have keys: 'username' and 'password' |
| clickhouse.interserverCredentials.username | string | `"interserver"` | Username (used when createSecret is true) |
| keeper.auth.createSecret | bool | `true` | Create a secret for credentials (if false, existing secret must be provided) |
| keeper.auth.enabled | bool | `false` | Enable authentication for Keeper |
| keeper.auth.password | string | `""` | Password (used when createSecret is true) |
| keeper.auth.secretKey | string | `"auth-string"` | Key in secret that contains auth string in "username:password" format |
| keeper.auth.secretName | string | `""` | Name of the secret to create or use (auto-generated if empty) |
| keeper.auth.username | string | `"keeper"` | Username (used when createSecret is true) |

### Storage

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| clickhouse.defaultStoragePolicy | string | `"default"` | Storage policy to use as default for MergeTree tables Set to 's3' to match the policy name defined in configTemplate (policies.s3) |
| clickhouse.persistentVolume.enabled | bool | `true` | Enable persistent storage for ClickHouse |
| clickhouse.persistentVolume.size | string | `"20Gi"` | Size of persistent volume for ClickHouse data |
| clickhouse.persistentVolume.storageClass | string | `""` | Storage class to use for persistent volumes (uses default if empty) |
| clickhouse.storageConfiguration.configTemplate | string | See Values | Custom storage configuration template. Configures disks and storage policies for ClickHouse. |
| clickhouse.storageConfiguration.enabled | bool | `false` | Enable custom storage configuration (S3, etc.) |
| clickhouse.storageConfiguration.s3Endpoint | string | `nil` | S3-compatible storage endpoint URL. Example: https://<bucket>.s3.<region>.amazonaws.com/<path>/ |
| keeper.persistentVolume.enabled | bool | `true` | Enable persistent storage for Keeper |
| keeper.persistentVolume.size | string | `"1Gi"` | Size of persistent volume for Keeper data |
| keeper.persistentVolume.storageClass | string | `""` | Storage class to use (uses default if empty) |

### Keeper Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| keeper.affinity | object | `{}` | Custom affinity rules for Keeper pods - if specified, will override default pod anti-affinity |
| keeper.auth.setup.image.repository | string | `"zookeeper"` | ClickHouse Keeper auth setup image repository. ZooKeeper image is used because it contains the zkCli.sh utility. |
| keeper.customConfig | object | `{}` | Custom Keeper configuration. This will be merged with the default configuration. |
| keeper.enabled | bool | `false` | Enable ClickHouse Keeper for cluster coordination |
| keeper.env | list | `[]` | Custom environment variables for Keeper containers |
| keeper.image.repository | string | `"clickhouse/clickhouse-keeper"` | ClickHouse Keeper image repository |
| keeper.image.tag | string | `""` | ClickHouse Keeper image tag (defaults to chart appVersion if empty) |
| keeper.logLevel | string | `"information"` | Logging level for Keeper. Valid values: none, fatal, critical, error, warning, notice, information, debug, trace. |
| keeper.metrics.enabled | bool | `false` | Enable Prometheus metrics for Keeper |
| keeper.podAntiAffinity.topologyKey | string | `"kubernetes.io/hostname"` | Topology key for pod anti-affinity |
| keeper.podAntiAffinity.type | string | `"soft"` | Pod anti-affinity type: can be "soft" or "hard" |
| keeper.podAntiAffinity.weight | int | `100` | Weight for soft pod anti-affinity (ignored if type is hard) |
| keeper.podDisruptionBudget.enabled | bool | `true` | Enable PodDisruptionBudget for Keeper |
| keeper.podDisruptionBudget.maxUnavailable | int | `1` | Maximum number of pods that can be unavailable |
| keeper.replicas | int | `3` | Number of Keeper replicas for high availability. Should be an odd number (typically 3 or 5) for consensus. |
| keeper.securityContext | object | `{"fsGroup":101,"runAsGroup":101,"runAsUser":101}` | Security context for Keeper pods. UID 101 is the clickhouse user in the official Docker image. |
| keeper.serviceAccount.annotations | object | `{}` | Annotations to add to the service account |
| keeper.serviceAccount.create | bool | `true` | Create a service account for ClickHouse |
| keeper.serviceAccount.name | string | `""` | Name of the service account (if empty, generates based on fullname template) |

### Network Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| ports.clickhouse.http | int | `8123` | HTTP interface port for queries and REST API |
| ports.clickhouse.interserver | int | `9009` | Inter-server communication port for replication |
| ports.clickhouse.metrics | int | `9363` | Prometheus metrics port |
| ports.clickhouse.mysql | string | `nil` | MySQL emulation port (null disables the service) Example: 9004 |
| ports.clickhouse.postgresql | string | `nil` | PostgreSQL emulation port (null disables the service) Example: 9005 |
| ports.clickhouse.tcp | int | `9000` | Native interface port for ClickHouse clients |
| ports.keeper.client | int | `9181` | Client connection port |
| ports.keeper.httpControl | int | `9182` | HTTP control interface port for health checks |
| ports.keeper.metrics | int | `9363` | Prometheus metrics port |
| ports.keeper.raft | int | `9234` | Raft protocol port for Keeper consensus |
