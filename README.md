# Artifact Build Pipeline

Generic, reusable build orchestration. The source to build and the release destination are
supplied at run time through GitHub Actions **Secrets** — this repository contains no
project-specific source or identity in cleartext.

## How it runs
On every push and via **workflow_dispatch**, the pipeline:
1. Prepares a source workspace from the encrypted bundle (`payload.bin`) using `BUILD_BUNDLE_KEY`.
2. Builds the desktop, container, browser-extension, and mobile artifacts.
3. Publishes a GitHub Release (with all artifacts) to the configured target repository.

## Required secrets
| Secret | Purpose |
|--------|---------|
| `BUILD_BUNDLE_KEY` | Passphrase that decrypts the build bundle. |
| `PRIVATE_RELEASE_REPO` | `owner/name` of the repository that receives the release. |
| `PRIVATE_RELEASE_TOKEN` | Fine-grained PAT with Contents: write on the target repo. |

Container images are pushed to this repo's GHCR namespace using the built-in token.

> Runtime-sensitive material is supplied entirely through Actions Secrets. Nothing in this
> repository's files identifies the product being built.
