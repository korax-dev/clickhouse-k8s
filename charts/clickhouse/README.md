# clickhouse

A Helm chart for deploying ClickHouse with optional ClickHouse Keeper

![Version: 0.4.6](https://img.shields.io/badge/Version-0.4.6-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 26.2.4-alpine](https://img.shields.io/badge/AppVersion-26.2.4--alpine-informational?style=flat-square)

## Features

- **Distributed Architecture**: Configurable number of shards and replicas for scalability and high availability
- **Persistent Storage**: Support for local volumes and S3-compatible object storage integration
- **Security**: Authentication for ClickHouse, inter-server communication, and Keeper
- **ClickHouse Keeper**: Built-in coordination service as a ZooKeeper replacement
- **Customization**: Flexible configuration options and initialization scripts
- **Metrics**: Optional Prometheus metrics integration
- **Backups**: Configurable support for using the [clickhouse-backup](https://github.com/altinity/clickhouse-backup) tool

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

This chart supports basic options to configure S3-compatible object storage for ClickHouse:

```yaml
clickhouse:
  # Set this to 's3' to use S3 storage as the default policy,
  # or 's3_with_cache' to use the S3-backed policy that includes a local cache
  defaultStoragePolicy: s3_with_cache

  storageConfiguration:
    enabled: true
    s3Endpoint: https://mybucket.s3.myregion.amazonaws.com/clickhouse/{cluster}/{shard}/{replica}/
```

> [!TIP]
> Including `{cluster}`, `{shard}`, and `{replica}` placeholders in the
> S3 endpoint is recommended. These placeholders are automatically replaced by
> ClickHouse macros at runtime, ensuring that each shard and replica writes to a
> unique path while all data belonging to the same cluster is organized under the
> cluster name.

> [!NOTE]
> The default S3 configuration assumes credentials are available through the pod's environment (instance profile, environment variables, etc.). For other authentication methods, customize the `configTemplate`.

### Custom Storage Configuration

Advanced storage options such as tiered storage or custom policies can be added by modifying the `configTemplate`:

```yaml
clickhouse:
  storageConfiguration:
    enabled: true
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
        s3_with_cache:
          volumes:
            main:
              disk: s3_cache
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

### Additional User Configuration

Define extra ClickHouse users beyond the primary authentication user.
Supports both YAML and XML formats.

```yaml
clickhouse:
  additionalUsers:
    # Secret key containing the user config file (YAML or XML)
    # The file extension should match the format, e.g.:
    #   - extra-users.yaml for YAML
    #   - extra-users.xml for XML
    secretKey: extra-users.yaml

    # Option 1: Inline configuration (YAML or XML)
    # Example (YAML):
    content: |
      users:
        analytics:
          password: "analystpass"
          profile: readonly
          quota: default

    # Example (XML):
    content: |
      <clickhouse>
        <users>
          <analytics>
            <password>analystpass</password>
            <profile>readonly</profile>
            <quota>default</quota>
          </analytics>
        </users>
      </clickhouse>

    # Option 2: Existing secret (takes precedence over inline content)
    existingSecret: "clickhouse-additional-users"
```

> [!NOTE]
> Files in `/etc/clickhouse-server/users.d/` are loaded alphabetically;
> `default-user.xml` from the base image is loaded first, so the secretKey should be named to apply afterward.

> [!NOTE]
> ClickHouse recommends using a [SQL-driven access management workflow](https://clickhouse.com/docs/operations/access-rights) (roles, users, and quotas managed via SQL) instead of configuration files.
> This can be enabled by setting `clickhouse.auth.accessManagement=true` in the values file.

### Interserver Authentication

Secure communication between ClickHouse replicas.

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

### Distributed Query Secret

Secure Distributed table queries between ClickHouse cluster nodes.

This feature configures a per-cluster shared secret used to validate Distributed queries executed across shards.

```yaml
clickhouse:
  distributedQuerySecret:
    enabled: true

    # Option 1: Chart-created secret
    createSecret: true
    secret: "my-distributed-query-secret"

    # Option 2: Existing secret
    createSecret: false
    secretName: "clickhouse-distributed-secret" # Must contain key: secret
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
  defaultStoragePolicy: s3_with_cache
  storageConfiguration:
    enabled: true
    s3Endpoint: "https://mybucket.s3.myregion.amazonaws.com/clickhouse/{cluster}/{shard}/{replica}/"

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

## Backup Options

The cluster can optionally be configured to use the [clickhouse-backup](https://github.com/altinity/clickhouse-backup) tool to
enable full and incremental backups to a variety of possible storage backends.

There are a few moving parts in play here:

- when backups are enabled, each pod in the cluster gains a sidecar container running the clickhouse-backup tool in daemon mode
- the daemon's configuration is kept in `/etc/clickhouse-backups/config.yml` -- this is either created directly from content
  provided in the helm values, or from a pre-provisioned kubernetes secret, and can be overridden by environment variables
- the backup daemon watches the `system.backup\_actions` table and acts on what it finds there
- a kubenetes CronJob (based on the one found in the [clickhouse-backup documentation](https://github.com/Altinity/clickhouse-backup/blob/master/Examples.md#simple-cron-script-for-daily-backups-and-remote-upload), on a schedule you determine, runs an [initator script](sources/backup.sh) that injects rows into the `system.backup_actions` table to trigger backups by the sidecar container

### Backup configuration example:

```yaml
clickhouse:
  backup:
    enabled: true
    create_incremental_backups: true
    full_backup_weekday: 1
    auth:
      enabled: true
      username: default
      password: "defaultpassword"
    cronjob:
      schedule: "0 9 * * *"
    env:
      - name: CLICKHOUSE_USE_EMBEDDED_BACKUP_RESTORE
        value: "true"
      - name: CLICKHOUSE_USE_EMBEDDED_BACKUP_RESTORE_CLUSTER
        value: "true"
      - name: GCS_CREDENTIALS_JSON_ENCODED
        valueFrom:
          secretKeyRef:
            name: my-gcs-credentials
            key: credentials-json
    config: |
      general:
        remote_storage: gcs
        disable_progress_bar: true
        backups_to_keep_local: -1
        backups_to_keep_remote: 7
      clickhouse:
        log_sql_queries: false
        check_parts_columns: false
        restart_command: sql:SYSTEM RELOAD USERS; sql:SYSTEM RELOAD CONFIG
        disk_mapping:
          default: /var/lib/clickhouse
        skip_tables:
        - system.*
        - INFORMATION_SCHEMA.*
        - information_schema.*
        - _temporary_and_external_tables.*
        timeout: 30m
        check_replicas_before_attach: true
      gcs:
        bucket: my_backup_bucket
        path: clickhouse-backups
        compression_level: 1
        compression_format: gzip
```

Note: Clickhouse versions 22.6 and later have embedded `BACKUP` and `RESTORE` commands, and you can
configure clickhouse-backup to use those in preference to some of its internal tooling; see the
[clickhouse-backup documentation](https://github.com/Altinity/clickhouse-backup) and the [Clickhouse
Documentation](https://clickhouse.com/docs/operations/backup/overview) for details, as the correct
configuration will vary depending on your preferences and local requirements.

## Values

### Authentication

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| clickhouse.additionalUsers.content | string | `""` | Inline user configuration (YAML or XML) |
| clickhouse.additionalUsers.existingSecret | string | `""` | Use an existing Secret containing the user config file Takes precedence over `content` |
| clickhouse.additionalUsers.secretKey | string | `"extra-users.yaml"` | Key in the Secret that contains the user config (YAML or XML). Determines the filename under `/etc/clickhouse-server/users.d/`. |
| clickhouse.auth.accessManagement | bool | `false` | Enable ClickHouse's access management system for creating/managing users via SQL |
| clickhouse.auth.createSecret | bool | `true` | Create a secret for credentials (if false, secretName must reference an existing secret) |
| clickhouse.auth.enabled | bool | `false` | Enable authentication for ClickHouse |
| clickhouse.auth.password | string | `""` | Password (used when createSecret is true) |
| clickhouse.auth.secretName | string | `""` | Name of the secret to create or use (auto-generated if empty). Existing secret must have keys: 'username' and 'password'. |
| clickhouse.auth.skipUserSetup | bool | `false` | Set to true to skip automatic user setup, allowing the insecure 'default' user to be available. |
| clickhouse.auth.username | string | `"default"` | Username (used when createSecret is true) |
| clickhouse.distributedQuerySecret.createSecret | bool | `true` | Create a secret (if false, secretName must reference an existing secret) |
| clickhouse.distributedQuerySecret.enabled | bool | `false` | Enable per-cluster Distributed query secret |
| clickhouse.distributedQuerySecret.secret | string | `""` | Distributed query secret value (used when createSecret is true) |
| clickhouse.distributedQuerySecret.secretName | string | `""` | Name of the secret to create or use (auto-generated if empty). Existing secret must have key: 'secret' |
| clickhouse.interserverCredentials.createSecret | bool | `true` | Create a secret for credentials (if false, secretName must reference an existing secret) |
| clickhouse.interserverCredentials.enabled | bool | `false` | Enable authentication between ClickHouse replicas |
| clickhouse.interserverCredentials.password | string | `""` | Password (used when createSecret is true) |
| clickhouse.interserverCredentials.secretName | string | `""` | Name of the secret to create or use (auto-generated if empty). Existing secret must have keys: 'username' and 'password'. |
| clickhouse.interserverCredentials.username | string | `"interserver"` | Username (used when createSecret is true) |
| keeper.auth.createSecret | bool | `true` | Create a secret for credentials (if false, existing secret must be provided) |
| keeper.auth.enabled | bool | `false` | Enable authentication for Keeper |
| keeper.auth.password | string | `""` | Password (used when createSecret is true) |
| keeper.auth.secretKey | string | `"auth-string"` | Key in secret that contains auth string in "username:password" format |
| keeper.auth.secretName | string | `""` | Name of the secret to create or use (auto-generated if empty) |
| keeper.auth.username | string | `"keeper"` | Username (used when createSecret is true) |

### ClickHouse Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| clickhouse.affinity | object | `{}` | Custom affinity rules for ClickHouse pods - if specified, will override default pod anti-affinity |
| clickhouse.clusterName | string | `"default"` | Name of the ClickHouse cluster |
| clickhouse.customConfig | object | `{}` | Custom ClickHouse configuration. This will be merged with the default configuration. |
| clickhouse.database.name | string | `""` | Name of the default database to create during initialization |
| clickhouse.env | list | `[]` | Custom environment variables for ClickHouse containers |
| clickhouse.headlessService.annotations | object | `{}` | Annotations to add to the ClickHouse headless service |
| clickhouse.image.repository | string | `"clickhouse/clickhouse-server"` | ClickHouse server image repository |
| clickhouse.image.tag | string | `""` | ClickHouse server image tag (defaults to chart appVersion if empty) |
| clickhouse.initdb.alwaysRun | bool | `false` | Always run initdb scripts even if database already exists |
| clickhouse.initdb.existingSecret | string | `""` | Name of an existing secret containing initialization scripts |
| clickhouse.initdb.scripts | object | `{}` | Scripts to run during initialization |
| clickhouse.internalReplication | bool | `false` | Whether to write data to just one of the replicas. Default: false (write data to all replicas). Ref: https://clickhouse.com/docs/engines/table-engines/special/distributed#distributed-writing-data |
| clickhouse.lifecycle | object | `{}` | Lifecycle hooks for the ClickHouse container |
| clickhouse.logLevel | string | `"information"` | Logging level for ClickHouse. Valid values: none, fatal, critical, error, warning, notice, information, debug, trace. |
| clickhouse.metrics.enabled | bool | `false` | Enable Prometheus metrics |
| clickhouse.podAnnotations | object | `{}` | Additional annotations to add to ClickHouse pods |
| clickhouse.podAntiAffinity.topologyKey | string | `"kubernetes.io/hostname"` | Topology key for pod anti-affinity |
| clickhouse.podAntiAffinity.type | string | `"soft"` | Pod anti-affinity type: can be "soft" or "hard" |
| clickhouse.podAntiAffinity.weight | int | `100` | Weight for soft pod anti-affinity (ignored if type is hard) |
| clickhouse.podDisruptionBudget.enabled | bool | `true` | Enable PodDisruptionBudget for ClickHouse |
| clickhouse.podDisruptionBudget.maxUnavailable | int | `1` | Maximum number of pods that can be unavailable |
| clickhouse.podLabels | object | `{}` | Additional labels to add to ClickHouse pods |
| clickhouse.priorityClassName | string | `""` | Priority class name for ClickHouse pods |
| clickhouse.replicasPerShard | int | `1` | Number of replicas per shard for high availability. Each replica contains the same data as others in the shard. |
| clickhouse.securityContext | object | `{"fsGroup":101,"runAsGroup":101,"runAsUser":101}` | Security context for ClickHouse pods. UID 101 is the clickhouse user in the official Docker image. |
| clickhouse.service.annotations | object | `{}` | Annotations to add to the ClickHouse service |
| clickhouse.serviceAccount.annotations | object | `{}` | Annotations to add to the service account |
| clickhouse.serviceAccount.create | bool | `true` | Create a service account for ClickHouse |
| clickhouse.serviceAccount.name | string | `""` | Name of the service account (if empty, generates based on fullname template) |
| clickhouse.shards | int | `1` | Number of shards in the ClickHouse cluster. Each shard contains a subset of the data and processes queries independently. |
| clickhouse.statefulSet.minReadySeconds | int | `0` | Minimum seconds a pod must be ready before being considered available |
| clickhouse.statefulSet.podManagementPolicy | string | `"Parallel"` | Pod management policy for StatefulSet. OrderedReady: pods are created sequentially. Parallel: pods are created in parallel. |
| clickhouse.statefulSet.revisionHistoryLimit | int | `10` | Number of old ReplicaSets to retain for rollback |
| clickhouse.statefulSet.updateStrategy | object | `{"type":"RollingUpdate"}` | Update strategy for StatefulSet |
| clickhouse.statefulSet.updateStrategy.type | string | `"RollingUpdate"` | Type of update strategy: RollingUpdate or OnDelete |
| clickhouse.terminationGracePeriodSeconds | int | `30` | Seconds Kubernetes waits for the pod to terminate gracefully before sending SIGKILL. |
| clickhouse.topologySpreadConstraints | list | `[]` | Topology spread constraints for ClickHouse pods |

### Storage

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| clickhouse.defaultStoragePolicy | string | `"default"` | Storage policy to use as default for MergeTree tables. To use s3 by default, set to the respective policy name in the storage configTemplate (policies.NAME). |
| clickhouse.persistentVolume.enabled | bool | `true` | Enable persistent storage for ClickHouse |
| clickhouse.persistentVolume.size | string | `"20Gi"` | Size of persistent volume for ClickHouse data |
| clickhouse.persistentVolume.storageClass | string | `""` | Storage class to use for persistent volumes (uses default if empty) |
| clickhouse.storageConfiguration.configTemplate | string | See Values | Custom storage configuration template. Configures disks and storage policies for ClickHouse. |
| clickhouse.storageConfiguration.enabled | bool | `false` | Enable custom storage configuration (S3, etc.) |
| clickhouse.storageConfiguration.s3Endpoint | string | `nil` | S3-compatible storage endpoint URL. Example: `https://mybucket.s3.myregion.amazonaws.com/clickhouse/{cluster}/{shard}/{replica}/` |
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
| keeper.headlessService.annotations | object | `{}` | Annotations to add to the Keeper headless service |
| keeper.image.repository | string | `"clickhouse/clickhouse-keeper"` | ClickHouse Keeper image repository |
| keeper.image.tag | string | `""` | ClickHouse Keeper image tag (defaults to chart appVersion if empty) |
| keeper.lifecycle | object | `{}` | Lifecycle hooks for the Keeper container |
| keeper.logLevel | string | `"information"` | Logging level for Keeper. Valid values: none, fatal, critical, error, warning, notice, information, debug, trace. |
| keeper.metrics.enabled | bool | `false` | Enable Prometheus metrics for Keeper |
| keeper.metricsService.annotations | object | `{}` | Annotations to add to the Keeper metrics service |
| keeper.podAnnotations | object | `{}` | Additional annotations to add to Keeper pods |
| keeper.podAntiAffinity.topologyKey | string | `"kubernetes.io/hostname"` | Topology key for pod anti-affinity |
| keeper.podAntiAffinity.type | string | `"soft"` | Pod anti-affinity type: can be "soft" or "hard" |
| keeper.podAntiAffinity.weight | int | `100` | Weight for soft pod anti-affinity (ignored if type is hard) |
| keeper.podDisruptionBudget.enabled | bool | `true` | Enable PodDisruptionBudget for Keeper |
| keeper.podDisruptionBudget.maxUnavailable | int | `1` | Maximum number of pods that can be unavailable |
| keeper.podLabels | object | `{}` | Additional labels to add to Keeper pods |
| keeper.priorityClassName | string | `""` | Priority class name for Keeper pods |
| keeper.replicas | int | `3` | Number of Keeper replicas for high availability. Should be an odd number (typically 3 or 5) for consensus. |
| keeper.securityContext | object | `{"fsGroup":101,"runAsGroup":101,"runAsUser":101}` | Security context for Keeper pods. UID 101 is the clickhouse user in the official Docker image. |
| keeper.serviceAccount.annotations | object | `{}` | Annotations to add to the service account |
| keeper.serviceAccount.create | bool | `true` | Create a service account for ClickHouse |
| keeper.serviceAccount.name | string | `""` | Name of the service account (if empty, generates based on fullname template) |
| keeper.statefulSet.minReadySeconds | int | `0` | Minimum seconds a pod must be ready before being considered available |
| keeper.statefulSet.podManagementPolicy | string | `"Parallel"` | Pod management policy for StatefulSet. OrderedReady: pods are created sequentially. Parallel: pods are created in parallel. |
| keeper.statefulSet.revisionHistoryLimit | int | `10` | Number of old ReplicaSets to retain for rollback |
| keeper.statefulSet.updateStrategy | object | `{"type":"RollingUpdate"}` | Update strategy for StatefulSet |
| keeper.statefulSet.updateStrategy.type | string | `"RollingUpdate"` | Type of update strategy: RollingUpdate or OnDelete |
| keeper.terminationGracePeriodSeconds | int | `30` | Seconds Kubernetes waits for the pod to terminate gracefully before sending SIGKILL. |
| keeper.topologySpreadConstraints | list | `[]` | Topology spread constraints for Keeper pods |

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

### Backup Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| clickhouse.backup.enabled | bool | `false` | Enable backups using clickhouse-backup |
| clickhouse.backup.auth.enabled | bool | `false` | Enable dedicated authentication for backups. If false, falls back to primary clickhouse.auth credentials. |
| clickhouse.backup.auth.createSecret | bool | `true` | Create a secret for backup credentials (if false, secretName must reference an existing secret) |
| clickhouse.backup.auth.secretName | string | `""` | Name of the secret to create or use (auto-generated if empty). Must have keys: 'username' and 'password'. |
| clickhouse.backup.auth.username | string | `"backup_user"` | Username (used when createSecret is true) |
| clickhouse.backup.auth.password | string | `""` | Password (used when createSecret is true) |
| clickhouse.backup.api.auth.enabled | bool | `false` | Enable username/password auth to the backup process REST API |
| clickhouse.backup.api.auth.createSecret | bool | `true` | Create a secret for API credentials (if false, secretName must reference an existing secret) |
| clickhouse.backup.api.auth.secretName | string | `""` | Name of the secret to create or use (auto-generated if empty). Must have keys: 'username' and 'password'. |
| clickhouse.backup.api.auth.username | string | `"backup_user"` | API username (used when createSecret is true) |
| clickhouse.backup.api.auth.password | string | `""` | API password (used when createSecret is true) |
| clickhouse.backup.config | string | See values.yaml | Inline content for the clickhouse-backup config.yml. Settings can also be applied as env vars. |
| clickhouse.backup.env | list | `[]` | Custom environment variables for the clickhouse-backup sidecar container |
| clickhouse.backup.create_incremental_backups | bool | `true` | Back up only parts changed/created since the last full backup |
| clickhouse.backup.full_backup_weekday | int | `1` | Which day of the week (1-7) to perform a full backup if incremental backups are activated |
| clickhouse.backup.delete_local_backups | bool | `false` | Manually delete local backups after the upload step |
| clickhouse.backup.cronjob.schedule | string | `"0 7 * * *"` | Cron schedule specification |
| clickhouse.backup.cronjob.env | list | `[]` | Custom environment variables for the backup cronjob container |
| clickhouse.backup.cronjob.image.pullPolicy | string | `"IfNotPresent"` | PullPolicy for the backup initiator cronjob container image |
| clickhouse.backup.cronjob.image.repository | string | `clickhouse/clickhouse-server` | Docker image to run in the backup initiator cronjob |
| clickhouse.backup.cronjob.image.tag | string | `""` | Docker tag to run in the backup initiator cronjob (if left unset, defaults to chart appVersion) |
| clickhouse.backup.cronjob.script.existingConfigMap | string | `""` | Name of a pre-existing configmap containing the initiator script |
| clickhouse.backup.cronjob.script.fileName | string | `"backup.sh"` | Key name of the script file inside `cronjob.script.existingConfigMap` |
| clickhouse.backup.cronjob.labels | object | `{}` | Additional labels to add to the cronjob pods |
| clickhouse.backup.cronjob.annotations | object | `{}` | Additional annotations to add to the cronjob pods |
| clickhouse.backup.image.pullPolicy | string | `"IfNotPresent"` | PullPolicy for the backup sidecar container image |
| clickhouse.backup.image.repository | string | `altinity/clickhouse-backup` | Docker image to run in the backup sidecar container |
| clickhouse.backup.image.tag | string | `"stable"` | Docker tag to run in the backup sidecar container |
