# Starting Cloud Foundry and Stratos

This guide starts Cloud Foundry (CF) on kind together with the Stratos web console, with or without a proxy.

The commands are the same in both cases. `Makefile.proxy` detects the proxy from the environment or from `/etc/environment`. The files of this repo stay unchanged.

## Prerequisites

- Ubuntu with `docker.io`, `docker-compose-v2`, `make`, `curl` and `jq`, or Debian 13 with `docker.io`, `docker-compose`, `make`, `curl` and `jq`
- `systemd-resolved`, if the domain has no DNS entry yet (see [Set the domain](#set-the-domain))
- Your user is in the `docker` group
- At least 8 CPU cores, 16 GB RAM and 100 GB disk

With a proxy, you also need:

- The proxy in `/etc/environment`, for example:

  ```bash
  http_proxy=http://proxy.example:3128
  https_proxy=http://proxy.example:3128
  no_proxy=localhost,127.0.0.1
  ```

- The proxy set for the Docker service, for example in `/etc/systemd/system/docker.service.d/http-proxy.conf`
- All hosts from [WHITELIST.md](WHITELIST.md) allowed on the proxy
- On Debian, the proxy for `apt` in `/etc/apt/apt.conf.d/95proxy`, because `sudo` does not read `/etc/environment` there:

  ```
  Acquire::http::Proxy "http://proxy.example:3128";
  Acquire::https::Proxy "http://proxy.example:3128";
  ```

## Set the domain

Without any configuration, CF uses the domain `127-0-0-1.nip.io` and can only be reached on the server itself. To allow access from other machines, create `proxy/config.env`:

```bash
cp proxy/config.env.example proxy/config.env
```

Enter the server IP and your own domain:

```bash
CF_HOST_IP=10.1.2.3
CLUSTER_DOMAIN=cf-test.example.internal
```

This file applies to this server only. Avoid the `.local` suffix, because it can conflict with mDNS.

If `nip.io` is allowed on your network, `CF_HOST_IP` is enough. The domain then follows from it, for example `10-1-2-3.nip.io`.

After a change you need to rebuild CF, which removes all apps:

```bash
make -f Makefile.proxy down host-setup up
```

## Once per server

```bash
make -f Makefile.proxy host-setup
```

This command needs `sudo`. It raises the inotify limits and loads the NFS modules. If the domain does not point to the server IP, it also sets up a local `dnsmasq`. That only covers the server itself.

## Start

```bash
make -f Makefile.proxy up          # checks the host and installs CF
make -f Makefile.proxy login       # logs in the CF CLI
make -f Makefile.proxy bootstrap   # creates an org and space, uploads buildpacks
make -f Makefile.proxy stratos     # installs Stratos
```

`up` stops if the host check finds an error. You can also run the check on its own with `make -f Makefile.proxy preflight`.

Optionally, this command tests the system with two test apps and removes them afterwards:

```bash
make -f Makefile.proxy verify
```

## Open Stratos

Stratos runs at `https://console.apps.<domain>`. The certificate is self-signed, so your browser shows a warning.

The user is `ccadmin`. This command shows the password:

```bash
grep CC_ADMIN_PASSWORD temp/secrets.env
```

With the default domain, the address only works on the server. From another machine, use an SSH tunnel:

```bash
ssh -L 8443:127.0.0.1:443 <user>@<server>
```

Stratos is then available there at `https://console.apps.127-0-0-1.nip.io:8443`.

## Access from other machines

Clients must reach the server IP on ports 443 and 2222. Port 2222 is for `cf ssh`. They also need two settings.

**1. Resolve the names.** The simplest option is a wildcard entry in your internal DNS, for example `*.cf-test.example.internal`. Clients then need nothing else.

Without a wildcard entry, this command generates the lines for the `hosts` file:

```bash
make -f Makefile.proxy hosts
```

Add the output on every client, in `/etc/hosts` on Linux, or as an administrator in `C:\Windows\System32\drivers\etc\hosts` on Windows. Every new app gets a new route, so generate the list again after a `cf push`.

**2. Bypass the proxy.** If the client uses a proxy itself, exclude the domain from it, for example:

```bash
export no_proxy="$no_proxy,.cf-test.example.internal"
```

This applies to the browser as well. Otherwise the client asks the proxy for an internal name and the request fails.

The `cf` CLI then works as usual:

```bash
cf api https://api.cf.cf-test.example.internal --skip-ssl-validation
cf login
```

## Use your own certificate

By default CF serves a generated certificate, so browsers warn and `cf` needs `--skip-ssl-validation`. To serve your own certificate instead, put these files into `proxy/tls/` on the server:

| File | Content |
|---|---|
| `tls.crt` | The certificate |
| `tls.key` | Its private key |
| `ca.crt` | The CA certificate, only needed for a private CA |

The certificate must cover these names, because a wildcard covers only one level:

- `*.cf.<domain>`
- `*.apps.<domain>`
- `*.blobstore.cf.<domain>`

Then run this after `login`:

```bash
make -f Makefile.proxy tls
```

The command checks the files before it changes anything. It only replaces the certificate on the gateway. The generated certificate stays in use inside CF. Git ignores `proxy/tls/`.

With a private CA, every client must trust that CA. After that, log in without the skip option:

```bash
cf login -a https://api.cf.<domain>
```

Run the command again in these cases:

- The certificate was renewed. Copy the new files first.
- `make -f Makefile.proxy up` ran again, because it resets the gateway.

Apps other than Stratos read the CA when they start, so restart any app that calls CF itself.

## Work with CF

On the server, always use the CF CLI in this shell:

```bash
make -f Makefile.proxy shell
cf apps
cf push -f examples/hello-js/manifest.yaml
```

In a normal shell, `cf` fails behind a proxy, because the request goes to the proxy instead of the local server.

## Stop

```bash
make -f Makefile.proxy down
```

This deletes the cluster and `temp/`, including all apps and passwords. The image caches stay, so the next start is faster.

## Restart the server

CF comes back after a reboot of the server without any action. Do not run `up` again. In the test, the API answered after about 2 minutes and Stratos after about 3.

Until then, the API and apps can answer with 503 or 404, and pods show `Error` or `Unknown` and restart several times. This is normal while the components wait for each other.

To check the result:

```bash
make -f Makefile.proxy verify
```

The server IP must stay the same, so use a static address or a DHCP reservation. If the proxy IP changes, run `make -f Makefile.proxy cf-proxy`.

If Stratos still crashes after a few minutes with `i/o timeout` to the gateway, the Cilium agent on a node has missed some pod addresses after the reboot, so the app is not allowed to reach them. Restart the Cilium agents and then Stratos:

```bash
make -f Makefile.proxy shell
kubectl -n kube-system delete pod -l k8s-app=cilium
kubectl -n kube-system rollout status daemonset/cilium
cf restart console
make -f Makefile.proxy verify
```

In the test, only the agent on the node that runs the apps was affected, but restarting all of them is safe.

## Troubleshooting

| Message | Cause and fix |
|---|---|
| `FAIL <host>` in `preflight` | The proxy does not let the host through. Check the allowlist, see [WHITELIST.md](WHITELIST.md). |
| `TLS not trusted` in `preflight` | The proxy probably intercepts TLS. This is not supported yet. |
| `proxy ... is routed into a Docker network` | The proxy network overlaps with a Docker network. Docker has to use other address ranges. |
| `cf push` reports `i/o timeout` during staging | The app cannot reach the proxy. Run `make -f Makefile.proxy cf-proxy` and push the app again. |
| Browser shows `no healthy upstream` | CF is still starting. Wait until `make -f Makefile.proxy stratos` has finished. |
| Stratos shows `certificate signed by unknown authority` | The `SSL_CERT_DIR` variable is missing. Run `make -f Makefile.proxy stratos` again. |
| `temp/ belongs to another domain` in `preflight` | The domain has changed. Run `make -f Makefile.proxy down` first, then start again. |
| An app cannot reach the internet | The proxy settings only apply after `cf restage <app>` if the app was pushed before `bootstrap`. |

## Limitations

- The proxy address is stored in the CF environment variables. If it contains a password, users with app access can read it.
- The flow with a proxy is fully tested on Ubuntu and Debian 13, including with a custom domain and from a second machine. On Debian 13, `verify` after a server reboot is tested as well. It is not part of the automated test.
- On every push, `.github/workflows/proxy-e2e.yaml` tests the flow without a proxy on a GitHub runner: `up`, `bootstrap`, `stratos`, `verify`, and `tls` with a test certificate.
- The flow without a proxy is tested with a custom domain, including `verify` after a server reboot.
- A custom certificate is tested with and without a proxy, with a private CA, but not with a public CA.
- The generated certificates are valid for 365 days. A custom certificate does not replace them inside CF, so the deployment has to be rebuilt before they expire.
