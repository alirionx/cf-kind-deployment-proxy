# Proxy allowlist for Cloud Foundry on kind

The proxy must allow these hosts for the server, so that the local Cloud Foundry test system can be installed and run. The list comes from the proxy log of a test run. It was then checked on an empty system with exactly these hosts allowed: installation, `cf push` and Stratos all completed without a blocked request.

The server only connects through the proxy over HTTP(S). It needs `CONNECT` on port 443, and HTTP on port 80 for the Ubuntu package sources.

## Container images

| Host | Port | Purpose |
|---|---|---|
| `registry-1.docker.io` | 443 | Docker Hub registry |
| `auth.docker.io` | 443 | Docker Hub authentication |
| `production.cloudfront.docker.com` | 443 | Docker Hub download CDN |
| `ghcr.io` | 443 | GitHub registry: Cloud Foundry images and Helm charts |
| `pkg-containers.githubusercontent.com` | 443 | GitHub registry download CDN |
| `quay.io` | 443 | Quay registry |
| `cdn01.quay.io` | 443 | Quay download CDN |
| `registry.k8s.io` | 443 | Kubernetes registry |
| `cdn.registry.k8s.io` | 443 | Kubernetes registry download CDN |
| `europe-west8-docker.pkg.dev` | 443 | Kubernetes registry, regional mirror |
| `us-central1-docker.pkg.dev` | 443 | Kubernetes registry, regional mirror |

## Tools

| Host | Port | Purpose |
|---|---|---|
| `github.com` | 443 | Downloads of kind, helmfile, yq, crane and Stratos |
| `release-assets.githubusercontent.com` | 443 | GitHub release downloads |
| `get.helm.sh` | 443 | Helm |
| `dl.k8s.io` | 443 | kubectl |
| `packages.cloudfoundry.org` | 443 | cf CLI |

## Helm charts

| Host | Port | Purpose |
|---|---|---|
| `charts.bitnami.com` | 443 | Bitnami chart index |
| `repo.broadcom.com` | 443 | Bitnami chart index, redirect target |
| `helm.cilium.io` | 443 | Cilium |
| `docs.tigera.io` | 443 | Calico chart index |
| `nats-io.github.io` | 443 | NATS |
| `istio-release.storage.googleapis.com` | 443 | Istio |

## App deployment (`cf push`)

| Host | Port | Purpose |
|---|---|---|
| `buildpacks.cloudfoundry.org` | 443 | Buildpack runtimes such as Node.js and Python |
| `registry.npmjs.org` | 443 | npm packages |

## Ubuntu packages

| Host | Port | Purpose |
|---|---|---|
| `archive.ubuntu.com` | 80 | Package sources |
| `security.ubuntu.com` | 80 | Security updates |

## Recommended wildcards

These hosts depend on the CDN or the location and can change. The test run took place on a different network, so other names may appear at your site. If possible, also allow:

- `*.quay.io`: The CDN host is numbered, for example `cdn01.quay.io`.
- `*.pkg.dev`: `registry.k8s.io` redirects to a different region depending on the location.
- `*.docker.com`: Docker Hub switches between CDNs.

If wildcards are not possible, the proxy log shows the blocked hosts after a failed run.

## Not included

This list covers the installation, Stratos and Node.js apps. Other apps may need further targets during `cf push`, for example Maven Central or PyPI.

The Ubuntu package sources are only needed to set up the server.
