# fullsend Configuration for OSAC

This directory contains fullsend-specific configuration and guidance documents to improve review quality.

## Files

### Core Configuration
- **config.yaml** - fullsend installation configuration (roles, allowed resources, issue creation targets, context files)
- **customized/agents/review.md** - Custom review agent with OSAC-specific system instructions

### Review Guidance (READ THESE FIRST)
- **REVIEW_GUIDE.md** - Anti-patterns, hallucination prevention, scope boundaries, framework-specific knowledge
- **INVARIANTS.md** - Architectural invariants to enforce and common bug patterns to detect
- **COMPONENT_MAP.md** - Cross-file relationships and where to look for related changes
- **MONITORING.md** - Quality metrics tracking, iteration triggers, feedback collection

### Helper Scripts
- **customized/scripts/analyze-pr-context.sh** - Uses graphify to discover cross-file relationships for PR files

## How fullsend Should Use These Documents

### Before Starting Review
1. Read `COMPONENT_MAP.md` to identify which files are related to the PR's changes
2. Read `INVARIANTS.md` to understand architectural invariants that must be preserved
3. Read `REVIEW_GUIDE.md` to understand OSAC-specific patterns and avoid false positives

### During Review
- Use COMPONENT_MAP.md's checklists to ensure all related files are reviewed
- Check each INVARIANTS.md rule against the PR changes
- Cross-reference REVIEW_GUIDE.md's "Architecture Facts" section before flagging framework/pattern issues

### Before Submitting Findings
- Run through INVARIANTS.md's "Self-Check Before Submitting Finding" checklist
- Verify finding is not in REVIEW_GUIDE.md's "What NOT to Review" list
- Check REVIEW_GUIDE.md's "Framework-Specific Knowledge" section to avoid hallucinations

## Key Improvements These Docs Provide

Based on feedback from OSAC team reviews, these documents address:

### Strengths to Preserve
✅ Cross-file documentation consistency checking  
✅ Architectural risk detection (blocking calls, topic mismatches)  
✅ Pattern violation detection  
✅ Well-calibrated severity ratings  

### Weaknesses to Fix
❌ **Hallucinations** → REVIEW_GUIDE.md "Architecture Facts" section provides ground truth  
❌ **Framework misunderstandings** → REVIEW_GUIDE.md "Framework-Specific Knowledge" section  
❌ **File type blind spots** → COMPONENT_MAP.md checklists ensure proto/Helm/SQL/CLI coverage  
❌ **Round 2+ noise** → REVIEW_GUIDE.md "Round 2+ Strategy" section  
❌ **Pre-existing pattern noise** → REVIEW_GUIDE.md "What NOT to Review" section  
❌ **Missing deep logic bugs** → INVARIANTS.md "Common Bug Patterns" section  

## High-Impact Review Checklist

Use this checklist on EVERY PR to maximize value:

### Phase 1: Scope & Context (5 min)
- [ ] Read PR description - what is the claimed scope and behavior?
- [ ] Check COMPONENT_MAP.md - which file types should this PR touch?
- [ ] Identify component(s) - read their AGENTS.md for design context
- [ ] Check if Round 2+ review - if so, focus on NEW issues only per REVIEW_GUIDE.md

### Phase 2: Architectural Invariants (10 min)
- [ ] Run through INVARIANTS.md "Architectural Invariants" section (6 rules)
- [ ] Check tenant isolation annotations on new tenant-scoped resources
- [ ] Verify owner reference pattern for parent-child relationships
- [ ] Check cross-component dependency order if multi-component PR
- [ ] Verify Helm chart sync for CRD/RBAC changes
- [ ] Check gRPC gateway header forwarding if custom headers used
- [ ] Verify OPA policy coverage for new tenant-scoped resources

### Phase 3: Bug Pattern Scan (10 min)
- [ ] UpdateMask field omissions (proto changes without handler update)
- [ ] CRD immutability bypass (optional fields breaking self == oldSelf)
- [ ] Ansible wait loops without failure exit (retries without failed_when)
- [ ] Regex validation edge cases (alternation order, escaping, anchors)
- [ ] Cross-PR dependency gaps (CRD field without reconciler)
- [ ] RBAC marker vs Helm chart drift
- [ ] Test coverage gaps (happy path only, no edge cases)
- [ ] Documentation staleness (AUTH.md, architecture-patterns.md, PR description)

### Phase 4: File Type Coverage (15 min)
Use COMPONENT_MAP.md's "File Types Reviewed" checklist:
- [ ] Proto definitions - validation, breaking changes
- [ ] CRD schemas - kubebuilder markers, validation
- [ ] Controller logic - reconcile, RBAC markers
- [ ] gRPC handlers - UpdateMask, error handling
- [ ] OPA policies - tenant isolation
- [ ] Ansible playbooks - module_defaults, wait conditions
- [ ] Helm templates - RBAC, values refs
- [ ] SQL migrations - DDL safety, down migration
- [ ] CLI commands - flags, help text
- [ ] Tests - edge cases coverage
- [ ] Documentation - AUTH.md, architecture-patterns.md sync

### Phase 5: Quality Check (5 min)
Before submitting findings, verify:
- [ ] Each finding has specific file:line reference
- [ ] Remediation is actionable (not vague "add validation")
- [ ] Issue is introduced by THIS PR (not pre-existing)
- [ ] Issue is not in REVIEW_GUIDE.md's "What NOT to Review" list
- [ ] Issue is not a hallucination (grep for evidence)
- [ ] Severity is calibrated per REVIEW_GUIDE.md guidelines

## Expected Review Time Budget

- **Small PR (<500 lines)**: 20-30 min
- **Medium PR (500-2000 lines)**: 40-60 min
- **Large PR (2000+ lines)**: 60-90 min
- **Round 2+ review**: 15-20 min (focus on NEW issues only)

If you have <3 findings in Round 2+, stop reviewing - diminishing returns.

## Using graphify for Enhanced Context

fullsend can leverage OSAC's knowledge graph for better cross-file analysis:

```bash
# Analyze PR context using graphify
.fullsend/customized/scripts/analyze-pr-context.sh path/to/changed/file.go

# Or query directly
graphify query "what files reference disk.proto"
graphify path "computeinstance_types.go" "Ansible playbook"
graphify explain "tenant isolation pattern"
```

This prevents fullsend from missing cross-file relationships that grep alone can't find.

## Setup Verification

After merging this PR, verify fullsend configuration:

```bash
# 1. Check config.yaml context_files are readable
for file in $(yq '.context_files[]' .fullsend/config.yaml); do
  if [[ -f "$file" ]]; then
    echo "✓ $file"
  else
    echo "✗ $file (missing)"
  fi
done

# 2. Verify graphify is available
if command -v graphify &>/dev/null && [[ -f graphify-out/graph.json ]]; then
  echo "✓ graphify integration ready"
else
  echo "⚠ graphify not available (install: uv tool install graphifyy)"
fi

# 3. Test PR context analysis script
.fullsend/customized/scripts/analyze-pr-context.sh \
  fulfillment-service/pkg/api/compute/v1alpha1/disk.proto
```

## Feedback Loop

If a finding is marked as false positive or "not actionable" by OSAC team:
1. Check which section of these docs should have caught it
2. Update the relevant doc to prevent future similar findings
3. Use MONITORING.md tracking template to log the issue
4. File issue to fullsend-ai/fullsend if it's a systemic problem

**Monthly cadence**:
- Week 1: Collect data on 3-5 PRs using MONITORING.md template
- Week 2: Analyze patterns, identify recurring issues
- Week 3: Update .fullsend/ docs based on patterns
- Week 4: Measure improvement against baseline metrics

These docs are living documents - they should evolve based on review feedback. See MONITORING.md for iteration triggers and success criteria.
