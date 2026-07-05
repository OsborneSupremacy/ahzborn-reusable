# ahzborn-reusable

Reusable build and CI/CD components

## Composite action: Build .NET Native AOT Lambda

This repo includes a composite action at `.github/actions/build-net-aot-lambda` that wraps `scripts/build-net-aot-lambda-function.sh`.

### Example usage

```yaml
name: Build Lambda AOT Zip

on:
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build Native AOT Lambda packages
        uses: ./.github/actions/build-net-aot-lambda
        with:
          target: all
          lambda-specs: |
            api|src/Foo.Create|FooCreate.zip|Foo.Create.csproj
            api|src/Foo.Get|FooGet.zip|Foo.Get.csproj
```

### Inputs

- `lambda-specs` (required): newline-delimited entries in the format `group|project_dir|zip_name|project_file`
- `target` (optional, default `all`)
- `repo-root` (optional, default `.`)
- `runtime` (optional, default `linux-arm64`)
- `configuration` (optional, default `Release`)
- `image` (optional, default `public.ecr.aws/sam/build-dotnet10:latest-arm64`)
- `platform` (optional, default `linux/arm64`)
- `dry-run` (optional, default `false`)

## Reusable workflow: Build .NET Native AOT Lambda

This repo also includes a reusable workflow at `.github/workflows/build-net-aot-lambda.yml` that can be called from other repositories via `workflow_call`.

### Example usage from another repository

```yaml
name: Build Lambda AOT Zip

on:
  workflow_dispatch:

jobs:
  build:
    uses: ben-osborne/ahzborn-reusable/.github/workflows/build-net-aot-lambda.yml@v1
    with:
      target: all
      lambda-specs: |
        api|src/Foo.Create|FooCreate.zip|Foo.Create.csproj
        api|src/Foo.Get|FooGet.zip|Foo.Get.csproj
```

## Versioning and tags

Use immutable tags for releases and a moving major tag for convenience.

### Suggested pattern

1. Create and push a release tag such as `v1.0.0`.
2. Major tag updates are automated by `.github/workflows/update-major-tag.yml`.
3. Update `v1` only when you ship a new compatible `v1.x.x` release.

```bash
git tag v1.0.0
git push origin v1.0.0
```

When a tag matching `vN.N.N` is pushed, the workflow automatically creates or force-moves the corresponding major tag `vN` to the same commit.

### Cross-repo references

- Direct composite action:

```yaml
uses: ben-osborne/ahzborn-reusable/.github/actions/build-net-aot-lambda@v1
```

- Reusable workflow:

```yaml
uses: ben-osborne/ahzborn-reusable/.github/workflows/build-net-aot-lambda.yml@v1
```

Prefer pinning to a full version tag such as `@v1.0.0` for strict reproducibility.
