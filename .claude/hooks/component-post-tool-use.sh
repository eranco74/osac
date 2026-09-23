#!/usr/bin/env bash

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
cwd=$(jq -r '.cwd // empty' <<<"$input")
file_path=$(jq -r '.tool_input.file_path // .tool_input.filePath // .tool_response.filePath // empty' <<<"$input")
[[ -n "$cwd" && -n "$file_path" ]] || exit 0

repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
if [[ "$file_path" != /* ]]; then
  file_path="$cwd/$file_path"
fi
file_dir=$(cd -P -- "$(dirname -- "$file_path")" 2>/dev/null && pwd) || exit 0
file_path="$file_dir/$(basename -- "$file_path")"
case "$file_path" in
  "$repo_root"/*) relative_path=${file_path#"$repo_root"/} ;;
  *) exit 0 ;;
esac

case "$relative_path" in
  proto/private/*.proto|proto/tests/*.proto)
    make -C "$repo_root/proto" lint
    make -C "$repo_root/proto" generate
    ;;
  fulfillment-service/go.mod)
    (cd "$repo_root/fulfillment-service" && go mod tidy)
    ;;
  osac-operator/go.mod)
    (cd "$repo_root/osac-operator" && go mod tidy)
    ;;
  osac-operator/api/go.mod)
    (cd "$repo_root/osac-operator/api" && go mod tidy)
    ;;
  osac-operator/api/v1alpha1/*_types.go)
    make -C "$repo_root/osac-operator" manifests generate
    ;;
esac
