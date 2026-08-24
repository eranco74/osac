#!/bin/bash
# Verify fullsend configuration is complete and all files are accessible

set -euo pipefail

echo "=== fullsend Configuration Verification ==="
echo ""

# Check if config.yaml exists
if [[ ! -f .fullsend/config.yaml ]]; then
    echo "✗ .fullsend/config.yaml not found"
    exit 1
fi
echo "✓ .fullsend/config.yaml exists"

# Check if context_files are readable
echo ""
echo "Checking context_files from config.yaml..."
missing_files=0

# Extract context_files from YAML (requires yq or manual parsing)
if command -v yq &>/dev/null; then
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            echo "  ✓ $file"
        else
            echo "  ✗ $file (missing)"
            ((missing_files++))
        fi
    done < <(yq '.context_files[]' .fullsend/config.yaml 2>/dev/null)
else
    # Fallback: manually check known files
    context_files=(
        ".fullsend/README.md"
        ".fullsend/REVIEW_GUIDE.md"
        ".fullsend/INVARIANTS.md"
        ".fullsend/COMPONENT_MAP.md"
        "AGENTS.md"
        "CLAUDE.md"
        "docs/ARCHITECTURE.md"
        "docs/CONVENTIONS.md"
        "fulfillment-service/docs/AUTH.md"
        ".claude/rules/architecture-patterns.md"
        ".claude/rules/networking-design-alignment.md"
        ".claude/rules/request-path-tracing.md"
        "bare-metal-fulfillment-operator/AGENTS.md"
        "fulfillment-service/AGENTS.md"
        "osac-aap/AGENTS.md"
        "osac-csi-driver/AGENTS.md"
        "osac-installer/AGENTS.md"
        "osac-operator/AGENTS.md"
        "osac-metering/AGENTS.md"
    )

    for file in "${context_files[@]}"; do
        if [[ -f "$file" ]]; then
            echo "  ✓ $file"
        else
            echo "  ✗ $file (missing)"
            ((missing_files++))
        fi
    done
fi

# Check custom agent file
echo ""
if [[ -f .fullsend/customized/agents/review.md ]]; then
    echo "✓ Custom review agent configured"
else
    echo "✗ Custom review agent missing"
    ((missing_files++))
fi

# Check helper script
if [[ -x .fullsend/customized/scripts/analyze-pr-context.sh ]]; then
    echo "✓ PR context analysis script ready"
else
    echo "✗ PR context analysis script missing or not executable"
    ((missing_files++))
fi

# Check graphify availability
echo ""
echo "Checking graphify integration..."
if command -v graphify &>/dev/null; then
    echo "  ✓ graphify installed"

    if [[ -f graphify-out/graph.json ]]; then
        echo "  ✓ graphify-out/graph.json exists"
        node_count=$(jq '.nodes | length' graphify-out/graph.json 2>/dev/null || echo "unknown")
        echo "    Graph has $node_count nodes"
    else
        echo "  ⚠ graphify-out/graph.json not found"
        echo "    Run: .claude/hooks/fetch-graphify-brain.sh"
    fi
else
    echo "  ⚠ graphify not installed (optional but recommended)"
    echo "    Install: uv tool install graphifyy"
fi

# Check auto-label workflow
echo ""
if [[ -f .github/workflows/auto-label-bot-prs.yaml ]]; then
    echo "✓ Auto-label bot PRs workflow configured"
else
    echo "⚠ Auto-label workflow missing (bot PRs won't trigger fullsend)"
fi

# Summary
echo ""
echo "=== Summary ==="
if [[ $missing_files -eq 0 ]]; then
    echo "✓ All required files present"
    echo ""
    echo "fullsend is ready to use with enhanced OSAC-specific configuration."
    echo ""
    echo "Next steps:"
    echo "  1. Test on next bot PR to verify context_files are loaded"
    echo "  2. Use MONITORING.md template to track review quality"
    echo "  3. Update docs monthly based on feedback (see MONITORING.md)"
    exit 0
else
    echo "✗ $missing_files file(s) missing or not accessible"
    echo ""
    echo "Fix missing files before fullsend can use enhanced configuration."
    exit 1
fi
