#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT_DEFAULT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RUNTIME_DEFAULT="linux-arm64"
CONFIGURATION_DEFAULT="Release"
PLATFORM_DEFAULT="linux/arm64"
AOT_BUILD_IMAGE_DEFAULT="public.ecr.aws/sam/build-dotnet10:latest-arm64"

RUNTIME="${RUNTIME:-$RUNTIME_DEFAULT}"
CONFIGURATION="${CONFIGURATION:-$CONFIGURATION_DEFAULT}"
PLATFORM="${PLATFORM:-$PLATFORM_DEFAULT}"
AOT_BUILD_IMAGE="${AOT_BUILD_IMAGE:-$AOT_BUILD_IMAGE_DEFAULT}"
REPO_ROOT="${REPO_ROOT:-$REPO_ROOT_DEFAULT}"

TARGET="all"
DRY_RUN="false"

# Spec format: group|project_dir|zip_name|project_file
LAMBDA_SPECS=()
BUILT_OUTPUTS=()

print_usage() {
  cat <<'EOF'
Project-agnostic Native AOT Lambda builder.

Usage:
  build-lambdas.sh [options]

Required:
  --lambda <group|project_dir|zip_name|project_file>
      Add a lambda build spec. Repeat for multiple lambdas.
      group: logical label (for --target filtering), e.g. api, auth, billing
      project_dir: path to the lambda project dir (relative to --repo-root or absolute)
      zip_name: output zip file name, e.g. CreateOrder.zip
      project_file: .csproj file name in project_dir, e.g. CreateOrder.csproj

Options:
  --target <group|all>
      Build only specs in the target group (default: all).

  --repo-root <path>
      Root path mounted into Docker (default: parent of script dir).

  --runtime <rid>
      dotnet runtime RID (default: linux-arm64).

  --configuration <name>
      dotnet configuration (default: Release).

  --image <container-image>
      Docker image with .NET Native AOT toolchain.

  --platform <docker-platform>
      Docker platform (default: linux/arm64).

  --dry-run
      Print what would be built without executing Docker/zip.

  -h, --help
      Show this help.

Examples:
  ./build-net-aot-lambda-function.sh \
    --lambda "api|src/Foo.Create|FooCreate.zip|Foo.Create.csproj" \
    --lambda "api|src/Foo.Get|FooGet.zip|Foo.Get.csproj"

  ./build-net-aot-lambda-function.sh \
    --target auth \
    --lambda "auth|services/authz|Authorizer.zip|Authz.csproj"

  ./build-net-aot-lambda-function.sh \
    --repo-root /path/to/repo \
    --lambda "billing|lambdas/invoice|Invoice.zip|Invoice.csproj"
EOF
}

add_lambda_spec() {
  local spec="$1"

  # Validate exactly 4 pipe-separated fields.
  local parts=0
  local tmp="$spec"
  while [[ "$tmp" == *"|"* ]]; do
    parts=$((parts + 1))
    tmp="${tmp#*|}"
  done
  parts=$((parts + 1))

  if [[ "$parts" -ne 4 ]]; then
    echo "error: --lambda expects 'group|project_dir|zip_name|project_file', got: $spec" >&2
    exit 1
  fi

  LAMBDA_SPECS+=("$spec")
}

resolve_project_dir() {
  local input_dir="$1"
  if [[ "$input_dir" == /* ]]; then
    printf '%s\n' "$input_dir"
  else
    printf '%s\n' "${REPO_ROOT}/${input_dir}"
  fi
}

build_lambda_aot() {
  local project_dir="$1"
  local zip_name="$2"
  local project_file="$3"

  if [[ ! -d "$project_dir" ]]; then
    echo "error: project directory does not exist: $project_dir" >&2
    exit 1
  fi

  local rel_project_dir
  case "$project_dir" in
    "${REPO_ROOT}"/*) rel_project_dir="${project_dir#"${REPO_ROOT}/"}" ;;
    *)
      echo "error: project directory must be under repo root for Docker mount: $project_dir" >&2
      echo "       repo root: $REPO_ROOT" >&2
      exit 1
      ;;
  esac

  local assembly_name="${project_file%.csproj}"
  local publish_dir="${project_dir}/bin/publish"
  local zip_path="${project_dir}/bin/${zip_name}"

  echo "Building (Native AOT) ${project_dir}/${zip_name}..."

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [dry-run] docker image: $AOT_BUILD_IMAGE"
    echo "  [dry-run] dotnet publish ${project_file} -o bin/publish -c ${CONFIGURATION} --runtime ${RUNTIME} --self-contained true"
    BUILT_OUTPUTS+=("$zip_path")
    return 0
  fi

  rm -f "$zip_path"

  docker run --rm \
    --platform "$PLATFORM" \
    --entrypoint /bin/bash \
    -v "${REPO_ROOT}":/workspace \
    -w "/workspace/${rel_project_dir}" \
    "$AOT_BUILD_IMAGE" \
    -c "set -euo pipefail; \
        dotnet publish ${project_file} -o bin/publish -c ${CONFIGURATION} --runtime ${RUNTIME} --self-contained true; \
        if [[ ! -f bin/publish/bootstrap ]]; then mv bin/publish/${assembly_name} bin/publish/bootstrap; fi; \
        chown -R $(id -u):$(id -g) bin"

  if [[ ! -f "${publish_dir}/bootstrap" ]]; then
    echo "error: Native AOT publish did not produce 'bootstrap' in ${publish_dir}" >&2
    exit 1
  fi

  pushd "$publish_dir" >/dev/null
  rm -f "../${zip_name}"
  zip -q "../${zip_name}" bootstrap
  popd >/dev/null

  BUILT_OUTPUTS+=("$zip_path")
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target)
        [[ $# -ge 2 ]] || { echo "error: --target requires a value" >&2; exit 1; }
        TARGET="$2"
        shift 2
        ;;
      --lambda)
        [[ $# -ge 2 ]] || { echo "error: --lambda requires a value" >&2; exit 1; }
        add_lambda_spec "$2"
        shift 2
        ;;
      --repo-root)
        [[ $# -ge 2 ]] || { echo "error: --repo-root requires a value" >&2; exit 1; }
        REPO_ROOT="$2"
        shift 2
        ;;
      --runtime)
        [[ $# -ge 2 ]] || { echo "error: --runtime requires a value" >&2; exit 1; }
        RUNTIME="$2"
        shift 2
        ;;
      --configuration)
        [[ $# -ge 2 ]] || { echo "error: --configuration requires a value" >&2; exit 1; }
        CONFIGURATION="$2"
        shift 2
        ;;
      --image)
        [[ $# -ge 2 ]] || { echo "error: --image requires a value" >&2; exit 1; }
        AOT_BUILD_IMAGE="$2"
        shift 2
        ;;
      --platform)
        [[ $# -ge 2 ]] || { echo "error: --platform requires a value" >&2; exit 1; }
        PLATFORM="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN="true"
        shift
        ;;
      -h|--help)
        print_usage
        exit 0
        ;;
      *)
        echo "error: unknown argument: $1" >&2
        print_usage >&2
        exit 1
        ;;
    esac
  done

  if [[ "${#LAMBDA_SPECS[@]}" -eq 0 ]]; then
    echo "error: at least one --lambda spec is required" >&2
    print_usage >&2
    exit 1
  fi
}

main() {
  parse_args "$@"

  REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"

  local built_any="false"

  for spec in "${LAMBDA_SPECS[@]}"; do
    local group project_dir_input zip_name project_file
    IFS='|' read -r group project_dir_input zip_name project_file <<<"$spec"

    if [[ "$TARGET" != "all" && "$group" != "$TARGET" ]]; then
      continue
    fi

    local project_dir
    project_dir="$(resolve_project_dir "$project_dir_input")"

    build_lambda_aot "$project_dir" "$zip_name" "$project_file"
    built_any="true"
  done

  if [[ "$built_any" != "true" ]]; then
    echo "No lambdas matched target '${TARGET}'."
    exit 0
  fi

  echo "Done. Lambda packages created:"
  local output
  for output in "${BUILT_OUTPUTS[@]}"; do
    echo "- ${output}"
  done
}

main "$@"