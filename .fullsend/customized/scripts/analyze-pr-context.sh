#!/bin/bash
# fullsend helper script: Analyze PR context using graphify knowledge graph
#
# This script uses graphify to discover cross-file relationships and component
# boundaries for PR files, helping fullsend provide better cross-file consistency
# checks and avoid missing related changes.
#
# Usage: .fullsend/customized/scripts/analyze-pr-context.sh <changed-file> [<changed-file> ...]

set -euo pipefail

# Check if graphify is available
if ! command -v graphify &> /dev/null; then
    echo "⚠️  graphify not installed - falling back to manual file analysis"
    echo "   Install with: uv tool install graphifyy"
    exit 0
fi

# Check if graph exists
if [[ ! -f "graphify-out/graph.json" ]]; then
    echo "⚠️  graphify-out/graph.json not found - run .claude/hooks/fetch-graphify-brain.sh"
    exit 0
fi

echo "=== PR Context Analysis (via graphify) ==="
echo ""

# Get list of changed files from args
changed_files=("$@")

if [[ ${#changed_files[@]} -eq 0 ]]; then
    echo "Usage: $0 <changed-file> [<changed-file> ...]"
    echo ""
    echo "Example:"
    echo "  $0 fulfillment-service/pkg/api/compute/v1alpha1/disk.proto"
    exit 1
fi

# Detect component for each file
declare -A components
for file in "${changed_files[@]}"; do
    component=$(echo "$file" | cut -d'/' -f1)
    components[$component]=1
done

echo "📦 Components touched by PR: ${!components[*]}"
echo ""

# For each component, suggest reading its AGENTS.md
echo "📖 Suggested component docs to read:"
for comp in "${!components[@]}"; do
    if [[ -f "$comp/AGENTS.md" ]]; then
        echo "   - $comp/AGENTS.md"
    fi
done
echo ""

# For each changed file, query graphify for related files
echo "🔍 Cross-file relationships (via graphify):"
echo ""

for file in "${changed_files[@]}"; do
    # Extract just the filename for cleaner queries
    filename=$(basename "$file")

    echo "File: $file"

    # Query 1: What files reference this file?
    echo "  Related files:"
    graphify query "what files reference $filename or import $filename" --budget 1000 2>/dev/null | \
        grep -E '^\s+NODE.*\[src=' | \
        sed 's/.*src=\([^ ]*\).*/    - \1/' | \
        head -10 || echo "    (none found)"

    # Query 2: If it's a proto file, find corresponding CRD/controller
    if [[ "$file" == *.proto ]]; then
        message_type=$(echo "$filename" | sed 's/.proto$//')
        echo "  Proto → CRD/Controller mapping:"
        graphify query "what files define types related to $message_type" --budget 1000 2>/dev/null | \
            grep -E '(types\.go|controller\.go)' | \
            sed 's/.*src=\([^ ]*\).*/    - \1/' | \
            head -5 || echo "    (none found)"
    fi

    # Query 3: If it's a CRD, find controller and playbooks
    if [[ "$file" == *_types.go ]]; then
        resource=$(basename "$file" | sed 's/_types.go$//')
        echo "  CRD → Controller/Playbook mapping:"
        graphify query "what files use $resource or reconcile $resource" --budget 1000 2>/dev/null | \
            grep -E '(controller\.go|\.yaml)' | \
            sed 's/.*src=\([^ ]*\).*/    - \1/' | \
            head -5 || echo "    (none found)"
    fi

    # Query 4: If it's an Ansible playbook, find controller that calls it
    if [[ "$file" == osac-aap/playbooks/*.yaml ]]; then
        playbook=$(basename "$file" .yaml)
        echo "  Playbook ← Controller mapping:"
        graphify query "what controllers or operators call $playbook" --budget 1000 2>/dev/null | \
            grep -E 'controller\.go' | \
            sed 's/.*src=\([^ ]*\).*/    - \1/' | \
            head -5 || echo "    (none found)"
    fi

    echo ""
done

echo "=== Checklist: Did PR update all related files? ==="
echo ""
echo "Use COMPONENT_MAP.md 'If X changed, did Y also change?' table to verify:"
echo ""
echo "- [ ] Proto changes → gRPC handler UpdateMask updated?"
echo "- [ ] Proto changes → Corresponding CRD types updated?"
echo "- [ ] CRD changes → Helm CRD copy synced?"
echo "- [ ] CRD RBAC markers → Helm ClusterRole updated?"
echo "- [ ] CRD schema → Controller reconcile logic updated?"
echo "- [ ] Controller extra_vars → Ansible playbook consumes them?"
echo "- [ ] New resource → OPA policy created?"
echo "- [ ] New resource → AUTH.md table updated?"
echo "- [ ] New resource → architecture-patterns.md hierarchy updated?"
echo ""
echo "See .fullsend/COMPONENT_MAP.md for complete checklist."
