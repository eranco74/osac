# fullsend Review Quality Monitoring & Iteration

This document tracks fullsend review quality over time and guides continuous improvement.

## Baseline Metrics (Pre-Enhancement)

Based on team feedback from PRs #236, #229, #159, #199:

| Metric | Value | Context |
|--------|-------|---------|
| **Signal-to-noise ratio** | 1/28 worst case, 50% typical | PR #199 Round 3: 1 actionable / 28 findings |
| **File type coverage** | ~30% | Missed proto, Helm, SQL, CLI in most reviews |
| **Hallucination rate** | ~15% | BSR version pins, Ansible module_defaults misunderstanding |
| **Round 2+ value** | Low | Diminishing returns, mostly noise |
| **Strengths preserved** | High | Doc consistency, architectural risks, pattern violations |

## Target Metrics (Post-Enhancement)

| Metric | Target | How to Measure |
|--------|--------|----------------|
| **Signal-to-noise ratio** | ≥60% | Actionable findings / total findings |
| **File type coverage** | ≥80% | File types reviewed / file types in PR |
| **Hallucination rate** | ≤5% | False positives contradicting REVIEW_GUIDE.md facts |
| **Round 2+ efficiency** | <3 findings or stop | Findings in Round 2+ |
| **Deep logic catches** | ≥1 per PR | Regex bugs, retry loops, immutability bypass, cross-PR gaps |

## Tracking Template

Use this template in PR comments when fullsend completes a review:

```markdown
## fullsend Review Quality Assessment

**PR**: #<number>
**Round**: 1 / 2 / 3+
**Review date**: YYYY-MM-DD
**Reviewer**: @<github-username>

### Findings Summary
- Total findings: X
- Actionable (fixed or accepted): Y
- False positives: Z
- Noise (pre-existing, out of scope): W

**Signal-to-noise ratio**: Y/X = ___%

### File Type Coverage
- [x] Proto definitions
- [ ] CRD schemas
- [x] Controller logic
- [ ] gRPC handlers
- [x] OPA policies
- [ ] Ansible playbooks
- [ ] Helm templates
- [ ] SQL migrations
- [x] CLI commands
- [x] Tests
- [x] Documentation

**Coverage**: __/14 = ___%

### High-Value Catches
1. [severity/category] Brief description - file:line
2. ...

### False Positives / Noise
1. [category] Brief description - why it's a false positive
2. ...

### Hallucinations Detected
- [ ] BSR version pin requests (contradicts REVIEW_GUIDE.md)
- [ ] Ansible module_defaults misunderstanding
- [ ] Kubernetes resource failure state assumptions
- [ ] OSAC annotation pattern misunderstanding
- [ ] Other: ___

### Deep Logic Checks Performed
- [ ] Regex validation edge cases
- [ ] Retry/wait loop failure exits
- [ ] CRD immutability bypass
- [ ] UpdateMask field omissions
- [ ] Cross-PR dependency gaps
- [ ] RBAC marker vs Helm drift
- [ ] Test edge case coverage

### Recommendations for fullsend Docs
- [ ] Add to REVIEW_GUIDE.md Architecture Facts: ___
- [ ] Add to INVARIANTS.md Bug Patterns: ___
- [ ] Update COMPONENT_MAP.md: ___
- [ ] No updates needed

### Overall Assessment
**Grade**: A / B / C / D / F

**Reasoning**: 

**Action items**:
1. 
2. 
```

## Review Quality Grades

### A Grade (Excellent)
- Signal-to-noise ≥70%
- File type coverage ≥80%
- Zero hallucinations
- ≥2 deep logic catches
- Round 2+ has <3 findings

**Example**: PR #236 Round 1 - caught health endpoint blocking call and Kafka topic mismatch missed by other tools.

### B Grade (Good)
- Signal-to-noise ≥60%
- File type coverage ≥60%
- ≤1 hallucination
- ≥1 deep logic catch
- Round 2+ stops appropriately

**Example**: PR #229 Round 1 - 3/6 actionable findings, caught doc staleness and pattern inconsistency.

### C Grade (Acceptable)
- Signal-to-noise ≥50%
- File type coverage ≥40%
- ≤2 hallucinations
- Some value added
- Round 2+ has 3-5 findings

### D Grade (Poor)
- Signal-to-noise <50%
- File type coverage <40%
- Multiple hallucinations
- Mostly noise
- Round 2+ wastes time

**Example**: PR #199 Round 2-3 - 1/28 actionable, many pre-existing issues flagged.

### F Grade (Harmful)
- Signal-to-noise <20%
- Hallucinations contradict documented facts
- Wastes reviewer time
- No value added

## Monthly Review Cadence

### Week 1: Collect Data
- Track 3-5 PRs using the template above
- Calculate average metrics
- Identify recurring false positive patterns

### Week 2: Analyze Patterns
- Which hallucinations recurred? (Add to REVIEW_GUIDE.md)
- Which bug patterns were missed? (Add to INVARIANTS.md)
- Which file types were systematically skipped? (Update COMPONENT_MAP.md checklist)

### Week 3: Update Documentation
- Add new Architecture Facts to REVIEW_GUIDE.md
- Add new Bug Patterns to INVARIANTS.md
- Enhance COMPONENT_MAP.md cross-references
- Update review.md agent instructions if systemic issues found

### Week 4: Measure Improvement
- Compare current month's metrics to baseline
- Document trends (improving / stable / degrading)
- Share findings with fullsend team if systemic tool issues

## Iteration Triggers

Update fullsend docs when:

### Hallucination Recurrence (≥2 times in same month)
→ Add to REVIEW_GUIDE.md "Architecture Facts" section

**Example**: If fullsend twice requests Buf Schema Registry version pins, add:
```markdown
**FACT**: OSAC does not use Buf Schema Registry. All proto imports are local Go module paths.
Evidence: `grep -r "buf.build" proto/` returns nothing.
```

### Bug Pattern Missed (≥2 times in same month)
→ Add to INVARIANTS.md "Common Bug Patterns" section

**Example**: If fullsend twice misses UpdateMask field omissions, add detection steps:
```markdown
### UpdateMask Field Omissions
**Pattern**: New field added to proto, not in UpdateMask allowlist.
**How to detect**: 
1. Find proto field additions: `git diff main -- '*.proto'`
2. Grep for UpdateMask in corresponding handler
3. Check if new field name is in allowlist
```

### File Type Systematically Skipped
→ Update COMPONENT_MAP.md and README.md checklists

**Example**: If fullsend consistently skips Helm charts, add prominently to checklist:
```markdown
⚠️ **CRITICAL**: Helm charts (helm/*/templates/*.yaml, helm/*/values.yaml) must be reviewed
for every osac-operator or osac-installer PR. Check RBAC, annotations, values refs.
```

### Cross-File Relationship Missed
→ Update COMPONENT_MAP.md "If X changed, did Y also change?" table

**Example**: If fullsend misses CRD → Helm chart sync, add:
```markdown
| CRD schema in osac-operator | Helm CRD copy in osac-installer/helm/osac-operator/crds/ |
```

## Success Criteria (3-Month Targets)

After 3 months of using enhanced fullsend configuration:

- [ ] **Signal-to-noise ratio** improved from 50% → ≥65%
- [ ] **File type coverage** improved from 30% → ≥70%
- [ ] **Hallucination rate** reduced from 15% → ≤5%
- [ ] **Round 2+ efficiency**: ≥80% of Round 2+ reviews have <3 findings or stop
- [ ] **Deep logic catches**: ≥1 per PR in ≥60% of reviews
- [ ] **Team satisfaction**: Reviewers rate fullsend as "helpful" ≥70% of the time

## Feedback Collection

### Quick Feedback (Every PR)
After each fullsend review, author marks findings:
- ✅ Actionable (will fix)
- ℹ️ Acknowledged (good catch, but won't fix for reason X)
- ❌ False positive (incorrect assumption)
- 🔇 Noise (pre-existing or out of scope)

### Detailed Feedback (Monthly)
Survey question for reviewers:
> "Rate fullsend's value this month: Harmful / Low / Medium / High / Critical"

Follow-up questions:
- Best catch this month?
- Most frustrating false positive?
- File types consistently missed?
- Suggested improvements to .fullsend/ docs?

## Integration with Team Workflow

### PR Review Workflow
1. **Author opens PR** → Auto-labeled `ready-for-review` (if from bot)
2. **fullsend reviews** → Posts findings as PR comment
3. **Author triages findings** → Marks with ✅/ℹ️/❌/🔇 emoji reactions
4. **Human reviewer reviews** → Can reference fullsend findings or ignore
5. **Weekly sync** → Team discusses high-value catches and persistent false positives

### Escalation Path
If fullsend review is consistently grade D or F:
1. **Week 1-2**: Update .fullsend/ docs per iteration triggers above
2. **Week 3-4**: If no improvement, file issue to fullsend-ai/fullsend with examples
3. **Week 5+**: If still no improvement, consider disabling specific review areas or fullsend entirely

## Example Analysis: PR #199

### What Happened
- **Round 1**: 1 real catch (README stale), rest noise or wrong
- **Round 2-3**: 0 new actionable findings, re-flagged intentional decisions
- **Signal-to-noise**: 1/28 = 3.6% (Grade F)

### Root Causes
1. **Hallucination**: Ansible module_defaults propagation not understood
2. **Pre-existing noise**: Flagged issues in 10+ other files
3. **Framework assumption**: Assumed all K8s resources have failure states
4. **No Round 2+ stop**: Kept reviewing despite <3 findings threshold

### Mitigations Applied
- ✅ Added Ansible module_defaults to REVIEW_GUIDE.md "Framework-Specific Knowledge"
- ✅ Added "What NOT to Review" rule: pre-existing patterns in 10+ files
- ✅ Added K8s resource failure states to REVIEW_GUIDE.md "Architecture Facts"
- ✅ Added Round 2+ strategy: stop if <3 findings

### Expected Improvement
If same PR reviewed with enhanced docs:
- Hallucination prevented by REVIEW_GUIDE.md
- Pre-existing noise filtered by "What NOT to Review" rules
- Round 2-3 would stop (0 findings < 3 threshold)
- **Projected signal-to-noise**: 1/1 = 100% (Grade A)

## graphify Integration Examples

fullsend should use graphify before grepping or reading multiple files:

### Example 1: Proto Change
```bash
# PR changes fulfillment-service/pkg/api/compute/v1alpha1/disk.proto
graphify query "what files reference disk.proto or DiskSpec"

# Returns:
# - osac-operator/api/v1alpha1/computeinstance_types.go
# - fulfillment-service/internal/service/compute/disk_service.go
# - fulfillment-service/test/integration/disk_test.go

# fullsend should then check if these files were updated in the PR
```

### Example 2: CRD Change
```bash
# PR changes osac-operator/api/v1alpha1/computeinstance_types.go
graphify path "computeinstance_types.go" "Ansible playbook"

# Returns path through:
# - computeinstance_controller.go (reconciler)
# - osac-aap/playbooks/workflows/compute/provision_instance.yaml

# fullsend should verify controller and playbook were updated
```

### Example 3: Cross-Component Dependency
```bash
# PR adds storage_tier field to ComputeInstanceDisk CRD
graphify query "what components depend on ComputeInstanceDisk"

# Returns:
# - fulfillment-service (proto definition)
# - osac-operator (CRD + controller)
# - osac-aap (Ansible playbooks consuming extra_vars)
# - osac-installer (Helm charts with RBAC)

# fullsend should verify all 4 components updated in SAME PR or flag cross-PR dependency
```

These graphify queries prevent fullsend from missing cross-file relationships that grep alone can't find.
