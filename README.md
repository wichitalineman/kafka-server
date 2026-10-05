# Kafka-as-a-service on RKE2 (Rancher Ansible-built clusters)

Per environment (dev, prod): one Kubernetes cluster, ~12 tenant Kafka clusters, one namespace each.

## 1. Platform (once per K8s cluster)
`platform/install-platform.yml` installs Strimzi (cluster-wide), external-dns (-> Route 53 zone for `kafka.example.com`),
an ACME ClusterIssuer (DNS-01 via Route 53) and a dedicated MetalLB `kafka-ip` pool. Charts and images come straight from the public repos/registries; the master node needs `helm`.

## 2. New customer (minutes)
```bash
cp tenants/example-prod.yaml tenants/<customer>.yaml     # edit tenant name, domain, size (TLS only, no auth)
                                                         # tenants/example-scram.yaml = SCRAM login + ACLs variant
helm upgrade --install <tenant> charts/kafka-tenant -n kafka-<tenant> --create-namespace -f tenants/<customer>.yaml
helm get notes <tenant> -n kafka-<tenant>                # paste to customer: endpoint + client props
```
Grow disk: raise `kafka.storage.size`, `helm upgrade` (StorageClass allows expansion; match any storage-side quota).
Tune broker properties under `kafka.config`; defaults are 3 brokers, RF 3, min.isr 2.

## Endpoints / security
- Bootstrap `<tenant>.kafka.example.com:9094` (one LB IP across brokers); each broker `<tenant>-bk1`, `-bk2`, `-bk3`.kafka.example.com:9094
  (clients must reach every broker — the bootstrap LB only serves metadata).
- TLS with a publicly-trusted cert per tenant, renewed 30d before expiry by cert-manager; Strimzi rolls brokers
  on renewal. Customers need no truststore. Auth per tenant: `none` (default) or `scram-sha-512` (+ ACLs).
  To use an internal CA instead, change `tls.issuerName`.

## Sizing (recommendation; validate with load tests)
| | Prod (per tenant) | Dev (per tenant) |
|---|---|---|
| Brokers | 3 x (2-4 vCPU, 8Gi, Xmx 4g) | 3 combined pods x (1-2 vCPU, 4Gi, Xmx 2g) |
| Controllers | 3 x (0.5-1 vCPU, 2Gi) | combined |
| Entity operator | ~0.5 vCPU, 512Mi | same |
| Disk | 500Gi-1Ti/broker | 100Gi/broker |

12 prod tenants ≈ 36 brokers + 36 controllers ≈ 100 vCPU / 400Gi requests, 48 LB IPs (+4 headroom per tenant).
Plan **8 dedicated workers x 16 vCPU / 64Gi** (prod) so brokers of a tenant land on different nodes with
headroom for a node loss; dev can run **4 x 8 vCPU / 32Gi**. Taint/label these workers for Kafka if the cluster is shared.
The existing 5-IP MetalLB pools are far too small; `kafka-ip` (192.0.2.1-250) is separate.

## Caveats to decide
1. **Let's Encrypt**: DNS-01 challenges are written to the public Route 53 zone by cert-manager; the zone must be publicly delegated (NS records at the registrar/parent).
2. **NFS-backed CSI (e.g. VAST)**: works, but Kafka on NFS needs `nfsvers=4`, and latency drives producer p99; benchmark before prod.
3. Chart passes `helm lint`/`helm template` (both examples) but has **not been applied to a cluster**. Strimzi v1 API + Kafka 4.2.x
   assumed; pin chart and Kafka versions once tested. MetalLB pool is `kafka-ip` (192.0.2.1-250).

4. **DNS-01 self-check**: cert-manager queries the zone's AWS nameservers on :53 before asking Let's Encrypt to validate. If nodes
   can't reach them ("i/o timeout" in `describe challenge`), set `dns01_recursive_nameservers` in `platform/vars.yml` to a resolver they can use.
5. `domain` is required in every tenant values file (no default); use your Route 53 zone.

6. **external-dns >= 0.22** changed its default annotation prefix; the platform values pin `--annotation-prefix=external-dns.alpha.kubernetes.io/` so the chart's annotations work.

## UI and rebalancing
- `ui.enabled: true` deploys AKHQ per tenant (browse topics/messages/groups) behind HAProxy ingress with an ACME cert.
- Rebalancing is not an AKHQ/Klaw feature. `cruiseControl.enabled` (default on) uses Strimzi's Cruise Control:
  apply a `KafkaRebalance` CR (`strimzi.io/rebalance: approve` annotation to run). Operators run this, not customers.
- Klaw adds topic/ACL request-approval workflow on top; add later if customers should self-request.

## Kafka 3.x
Set `kafka.version` / `kafka.metadataVersion` (e.g. 3.9.x / 3.9-IV0) — but each Strimzi release supports only a window
of Kafka versions, and Strimzi 1.x dropped 3.x. Running 3.x means an older operator (v1beta2 CRDs, `kafka.apiVersion: kafka.strimzi.io/v1beta2`),
which cannot coexist with 1.x CRDs in the same cluster. Prefer 4.x; upgrade tenants rather than deploy new 3.x.

## Adapting this repo (values to change for your environment)
All values below are placeholders / examples:
- `kafka.example.com` (README, `platform/vars.yml` `dns_zone`, `charts/kafka-tenant/values.yaml` `domain`): your Route 53 public zone.
- `192.0.2.1-192.0.2.250` (`platform/vars.yml` `metallb_kafka_pool`): a free range on your LAN for the MetalLB `kafka-ip` pool.
- `route53_hosted_zone_id`, `aws_access_key_id`, `aws_secret_access_key`, `acme_email` (`platform/vars.yml`): vault the keys; keep real values in an ignored `platform/vars-<env>.yml`.
- `kafka.storage.class` (empty = cluster default StorageClass): or name a class that allows volume expansion.
- `ui.ingressClass` and `tls.issuerName`: your ingress class and ClusterIssuer names.
- Kubeconfig/helm paths in `platform/vars.yml` assume RKE2 with a `masters` inventory group.

## Load test (`tools/loadtest/`)
Producer re-sends a 10KB payload at a set rate; consumer reads it back with a consumer group. Needs the Kafka CLI on PATH, or podman/docker
(runs `apache/kafka`; override with `KAFKA_IMAGE`). No truststore needed; the public cert is trusted by default.
```bash
cd tools/loadtest
export BOOTSTRAP=<tenant>.<domain>:9094
./create-topic.sh                        # topics are not auto-created
THROUGHPUT=100 ./producer.sh             # 100 x 10KB = ~1 MB/s; THROUGHPUT=-1 for unthrottled
./consumer.sh                            # in another shell; MESSAGES, GROUP tunable
```
SCRAM tenants: `SECURITY=scram KAFKA_USER=... KAFKA_PASSWORD=...`. Other knobs: `ACKS`, `LINGER_MS`, `BATCH_SIZE`, `COMPRESSION`, `NUM_RECORDS`,
`PARTITIONS`, `PAYLOAD_FILE` (single-line file; default is generated 10KB). The producer runs ~forever by default; NUM_RECORDS must stay under ~2 billion. Defaults live in `env.sh`.
