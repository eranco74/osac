# OSAC Architectural Invariants & Bug Patterns

This document lists architectural invariants and common bug patterns that fullsend should check during reviews.

## Architectural Invariants (MUST be preserved)

### 1. Tenant Isolation
Every tenant-scoped resource MUST have:
```yaml
metadata:
  annotations:
    osac.openshift.io/tenant: "<tenant-name>"
```

**Exception**: Provider-defined resources (NetworkClass, ExternalIPPool, StorageTier) are platform-scoped—tenants don't interact with them directly.

**How to check**: 
- Grep for `type: object` in CRD spec to find resource definitions
- Verify `osac.openshift.io/tenant` annotation is documented or enforced
- Check OPA policies in `fulfillment-service/pkg/authz/policies/<resource>.rego` for tenant filtering

### 2. Owner Reference Pattern
Parent-child relationships use annotations, NOT `metadata.ownerReferences[]`:
```yaml
metadata:
  annotations:
    osac.openshift.io/owner-reference: "<parent-type>/<parent-name>"
```

**Why**: Standard owner references trigger Kubernetes garbage collection. OSAC uses annotations to track logical hierarchy without automatic deletion.

**How to check**:
- Look for new resource relationships in architecture-patterns.md
- Verify annotation is set in controller reconcile logic or gRPC handler
- Grep for `.ownerReferences` in new code—should NOT be used

### 3. Cross-Component Dependency Order
When a PR spans multiple components, changes MUST land in dependency order:

```
fulfillment-service (proto changes)
  ↓
osac-operator (CRD + controller consuming proto types)
  ↓
osac-aap (Ansible playbooks consuming CRD fields via extra_vars)
  ↓
osac-installer (RBAC, Helm chart updates)
```

**How to check**:
- If proto changes in `fulfillment-service/pkg/api/`, check if osac-operator controllers are updated in SAME PR
- If CRD schema changes in osac-operator, check if Ansible playbooks consume new fields
- If new RBAC verbs added, check if `osac-installer/helm/*/templates/clusterrole.yaml` is updated

### 4. Helm Chart Sync
CRD changes in osac-operator MUST be synced to Helm charts:

1. Controller `// +kubebuilder:rbac:` markers → `osac-installer/helm/osac-operator/templates/clusterrole.yaml`
2. CRD YAML in `osac-operator/config/crd/bases/` → `osac-installer/helm/osac-operator/crds/`

**How to check**:
- Run `git diff` on `osac-operator/config/crd/bases/` and `osac-installer/helm/osac-operator/crds/`—should match
- Compare `// +kubebuilder:rbac:` lines to Helm ClusterRole rules
- Check if PR touches one but not the other (indicates missed sync)

### 5. gRPC Gateway Header Forwarding
Custom HTTP headers require explicit allowlist in gateway config:

**File**: `fulfillment-service/internal/cmd/service/start/restgateway/start_rest_gateway_cmd.go`

**Default**: Only permanent HTTP headers + `Grpc-Metadata-*` prefix are forwarded.

**How to check**:
- If PR adds feature relying on custom HTTP header (e.g., `X-Request-ID`, `X-Feature-Flag`)
- Verify gateway config adds header to `HeaderMatcher` allowlist
- Or verify header is renamed to `Grpc-Metadata-<name>` format

### 6. OPA Policy Coverage
New tenant-scoped resources MUST have OPA policy:

**File**: `fulfillment-service/pkg/authz/policies/<resource>.rego`

**Required rules**:
- `allow_<action>` for each RBAC verb (create, read, update, delete)
- Tenant isolation: `input.metadata.annotations["osac.openshift.io/tenant"] == input.user.tenant`
- Cross-resource references: Subnet can only reference VirtualNetwork in same tenant

**How to check**:
- Grep for new CRD type names in `pkg/authz/policies/`
- Verify policy file exists for new tenant-scoped resources
- Check `AUTH.md` documents the RBAC verbs and tenant scoping rules

## Common Bug Patterns

### 1. UpdateMask Field Omissions
**Pattern**: New field added to proto message, but not to UpdateMask allowlist.

**Impact**: gRPC Update calls silently ignore the new field.

**How to detect**:
- Proto field added in `fulfillment-service/pkg/api/*/*.proto`
- Search for `ValidateUpdateMask` or `updateMask.Paths` in corresponding service handler
- Check if new field name is in the allowlist

**Example**:
```go
// Bug: storage_tier added to proto but not to allowlist
allowedPaths := []string{"size_gib", "image"} // missing "storage_tier"
```

### 2. CRD Immutability Bypass
**Pattern**: Field claimed immutable via XValidation, but CEL expression doesn't cover new optional fields.

**Impact**: Immutable field can be changed after creation.

**How to detect**:
- PR adds optional field to struct with existing `self == oldSelf` validation
- Check if CEL expression is scoped to specific fields or entire struct
- Optional fields with `omitempty` may be absent in `oldSelf`, breaking equality check

**Example**:
```yaml
# Bug: new optional field not covered by immutability rule
x-kubernetes-validations:
- rule: "self.diskSpec == oldSelf.diskSpec"  # breaks if diskSpec.storageTier is absent in oldSelf
```

### 3. Ansible Wait Loop Without Failure Exit
**Pattern**: `retries:` and `delay:` set, but no `failed_when:` to exit early on non-retryable errors.

**Impact**: Loop exhausts all retries (e.g., 30 × 10s = 5 minutes) on a permanently failed resource.

**How to detect**:
- Task has `retries:` > 1 and `until:` condition
- No `failed_when:` checking for error states (e.g., CSV phase: Failed)
- Resource type has failure states (ClusterServiceVersion, Job, Pod) but not (StorageClass, Namespace)

**Example**:
```yaml
# Bug: will retry 30 times even if CSV is permanently failed
- name: Wait for CSV
  kubernetes.core.k8s_info:
    kind: ClusterServiceVersion
  register: csv
  until: csv.resources[0].status.phase == "Succeeded"
  retries: 30
  delay: 10
  # Missing: failed_when: csv.resources[0].status.phase == "Failed"
```

### 4. Regex Validation Edge Cases
**Pattern**: Regex looks correct but has subtle bugs (alternation order, escaping, anchors).

**Impact**: Accepts invalid input or rejects valid input.

**How to detect**:
- New `buf.validate.string.pattern` or CEL `matches()` expression
- Check alternation order: longest alternative first (`(tsx|ts)` → `(ts|tsx)` breaks `.tsx`)
- Check anchors: `^$` for full match, missing anchors allow partial matches
- Check escaping: `.` matches any char, `\.` matches literal dot

**Example**:
```protobuf
// Bug: accepts "10.5.3.b" (b suffix invalid for qemu-img)
string pattern = "^[0-9]+(\\.[0-9]+)?(k|m|g|b)?$";  // should be "(k|m|g)" only
```

### 5. Cross-PR Dependency Gaps
**Pattern**: PR 1 adds CRD field, PR 2 adds reconciler logic. Merging PR 1 first creates dead field.

**Impact**: Field accepted by API but never acted upon until PR 2 merges.

**How to detect**:
- CRD schema change without corresponding controller code change in SAME PR
- PR description says "reconciler mapping in separate PR" or references another PR number
- Grep for field name in `osac-operator/internal/controller/*_controller.go`—no hits

**Flag it**: This is a valid PR split IF documented, but risks merge order bugs. Suggest combining or noting the dependency.

### 6. RBAC Marker vs Helm Chart Drift
**Pattern**: Controller code has `// +kubebuilder:rbac:` marker, but Helm chart ClusterRole doesn't match.

**Impact**: Controller works in dev (kubebuilder auto-generates RBAC) but fails in production Helm deployment.

**How to detect**:
- Diff `osac-operator/config/rbac/role.yaml` (generated by kubebuilder) vs `osac-installer/helm/osac-operator/templates/clusterrole.yaml`
- New `// +kubebuilder:rbac:` marker in controller .go files
- Corresponding Helm chart not updated in same PR

### 7. Test Coverage Gaps (Happy Path Only)
**Pattern**: Tests exist but only cover the golden path, not edge cases from PR description.

**Impact**: Edge case bugs slip through CI.

**How to detect**:
- PR description claims "handles empty string vs absent for optional fields"
- Tests only check non-empty values
- No test cases for: empty string, absent field, wrong type, boundary values

**Example**:
```go
// Bug: no test for empty storage_tier vs absent storage_tier
func TestCreateDiskWithStorageTier(t *testing.T) {
    disk := &api.Disk{StorageTier: "fast-nvme"}  // only tests non-empty case
    // Missing: StorageTier: "" and StorageTier unset
}
```

### 8. Documentation Staleness
**Pattern**: Code changed, comments/docs not updated.

**Files to cross-check**:
- `docs/AUTH.md` - RBAC verbs table
- `docs/architecture-patterns.md` - resource hierarchy diagram
- `<component>/AGENTS.md` - component-specific architecture
- `osac-aap/CATALOG_ITEMS.md` - provider-defined catalog items
- PR description itself - does it match what was actually implemented?

**How to detect**:
- New CRD or RBAC verb → check AUTH.md
- New resource type → check architecture-patterns.md hierarchy
- New provider-defined resource → check CATALOG_ITEMS.md
- PR description says "Required" but code has `optional` → stale description

## High-Value Review Areas (Prioritize These)

1. **Health endpoint blocking calls**: `liveness` or `readiness` handlers making synchronous external API calls
2. **Kafka topic mismatches**: Consumer subscribed to `topic-v1` but producer publishes to `topic-v2`
3. **SQL migration safety**: Missing indexes on FK columns, dropping columns without multi-phase migration
4. **Prototype pollution**: Proto `map<string, X>` fields without validation on key format
5. **Credential leaks**: Secrets in error messages, logs, or PR descriptions

## Self-Check Before Submitting Finding

1. **Is this a regression introduced by THIS PR?** Don't flag pre-existing issues unless they're architectural risks.
2. **Can I cite a specific file:line?** Vague findings ("tests might not cover edge cases") are low value.
3. **Is my remediation actionable?** "Add validation" is vague. "Add `buf.validate.string.min_len = 1`" is actionable.
4. **Did I verify this in the actual code?** Don't assume based on patterns—grep for evidence.
5. **Is this documented as intentional?** Check component AGENTS.md before flagging design decisions.

## When to Skip Review (Avoid Noise)

- Round 2+ with <3 findings: diminishing returns, stop.
- Pre-existing pattern present in 10+ files: codebase-wide issue, not PR-specific.
- Stylistic preference with no correctness impact: team has chosen a style, defer to it.
- Generic security hardening irrelevant to PR scope: image SHA pinning on a networking PR.
