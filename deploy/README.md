# SLACube DAQ deploy tooling (Round 1)

Repeatable, idempotent build of one immutable release of the DAQ stack
(`daq`, `analysis`, `scripts`, `etc`) under a shared release store. Full
design and rationale: `docs/specs/2026/08/2026-08-08-1009-shared-release-store-daq-deploy-spec.md`
in the `slacube` workspace (D1-D15).

## What this is not

- Not a `slacube` subcommand (D9) — plain bash, invoked directly.
- Not a promotion tool. `deploy.sh` builds and seals a release, then prints
  the `ln -sfn` command to point `current` at it. It never runs that
  command. Promoting a release for the shifter (`/home/slacube`) is a
  separate, deliberate, human action outside this tool's scope for Round 1.
- Not a state manager. `deploy.sh` never writes `workdir/`, `queue/`, the
  shared config archive, or any dropbox (D5).

## Release / site / state model

- **Release** (`<store>/releases/<UTC>-<daq-sha7>/`): immutable, generated,
  relocatable. Code, venv, vendored `fzf`/`mdcat`/`uv`, a generated
  `env.sh`, and `manifest.json`. Sealed read-only after build (D3).
- **Site file** (per account, hand-written once, e.g. `~/slacube-dev.sh`
  from `site.sh.example`): selects a release, sets per-account state paths,
  the dropbox, and the PACMAN address. Never regenerated.
- **State** (per account or shared): `workdir/`, `queue/`,
  `/data/slacube/config-archive`, `/data/slacube/dropbox*`. Deploy never
  touches any of it.

## One-time setup (outside `deploy.sh`; both already done for the
`slacube-dev` target on `nu-daq01-ir2` as of 2026-08-08)

```sh
sudo mkdir -p /opt/slacube
sudo chown kvtsang:neutrino /opt/slacube
sudo chmod 2775 /opt/slacube

git clone /home/slacube/app/etc /data/slacube/config-archive
chgrp -R neutrino /data/slacube/config-archive
chmod -R g+w /data/slacube/config-archive
find /data/slacube/config-archive -type d -exec chmod g+s {} +
```

Cloning `etc` from the local production path (not GitHub) is what preserves
history GitHub doesn't have yet (tracker `issue-002`). This is a *read* of
`/home/slacube/app/etc` — the only interaction Round 1 has with the
shifter's install.

## Bootstrap

```sh
git clone --branch <daq-ref> https://github.com/SLACube/slacube-daq.git \
  /tmp/slacube-daq-bootstrap
/tmp/slacube-daq-bootstrap/deploy/deploy.sh \
  --config /tmp/slacube-daq-bootstrap/deploy/targets/slacube-dev.conf
```

`<daq-ref>` should match `targets/slacube-dev.conf`'s `REF_DAQ`; the
manifest records the resolved SHA either way, so a mismatch is detectable
after the fact.

Then, once per account:

```sh
cp deploy/site.sh.example ~/slacube-dev.sh
$EDITOR ~/slacube-dev.sh   # set SLACUBE_RELEASE to the printed release path
source ~/slacube-dev.sh
```

## Usage

```sh
deploy/deploy.sh --config deploy/targets/<name>.conf [overrides...]
```

Every value in the target `.conf` can be overridden per invocation:

| flag | overrides |
|---|---|
| `--store DIR` | release store root |
| `--ref REPO=BRANCH\|TAG\|SHA` | one of `daq`, `analysis`, `scripts`, `etc`; repeatable |
| `--python PATH` | interpreter used to build the release venv |
| `--ext-src DIR` | source dir for vendored `fzf`/`mdcat` |
| `--dropbox PATH` | dropbox reported in this release's banner |
| `--pacman-addr HOST` | recorded in manifest + banner only — see "Hardware & data safety" |
| `--keep N` | releases to retain (D14) |

`deploy.sh --from-manifest <release>/manifest.json [overrides...]` rebuilds
the exact same refs a past release used, defaulting all `--ref` values from
that manifest.

A missing required value (from neither the config file nor a flag) is a
hard error naming it — there are no silent defaults (D13).

### What it does, in order

`guard` → `preflight` → `resolve_refs` → `build_release` → `render_env` →
`write_manifest` → `seal_release` → `prune` → print a summary (release path,
per-repo SHA, Python version, the `source` line for a site file, and the
`ln -sfn` command to promote — **not executed**).

### Failure modes

- Bad ref, or the store/dropbox guard trips → nothing is written; abort
  before `build_release`.
- Build fails partway → an unsealed, unreferenced release directory is left
  behind. `current` never moved, so no running install degrades. Fix the
  cause and rerun; `prune` will eventually clean up the debris (it refuses
  to touch `current` or anything a discoverable site file still names, but
  a still-building release is unsealed and not yet referenced by anything,
  so it prunes like any other stale release once it ages out).
- `uv pip sync` can't satisfy `requirements-py38.txt` on the target Python →
  abort. The lock is the contract. Loosen it via `requirements.in` and
  recompile — never patch around it at deploy time:

  ```sh
  uv pip compile deploy/requirements.in \
    --python-version 3.8 \
    --output-file deploy/requirements-py38.txt
  ```

## Hardware & data safety

- `pacman19.local` (`10.11.10.110`) is one physical PACMAN, shared by every
  account that sources a release. `--pacman-addr` only changes `slacube
  power`'s ssh target (`bin/slacube:722-731`); the DAQ data path address
  comes from `scripts/larpix_qc/io/pacman.json`, copied into each workdir by
  `slacube env create`. **No flag redirects DAQ traffic.** The release
  banner states this on every `source`.
- `deploy.sh` **refuses unconditionally** — no override flag exists — if
  the configured dropbox resolves to `/data/slacube/dropbox`, or if the
  store or dropbox resolves under `/home/slacube`. Use
  `/data/slacube/dropbox_test` for development. This guard exists because
  the accident is reachable: the developer account is in the `neutrino`
  group and the live dropbox is group-writable.

## Invariants worth knowing before touching this

- `env.sh.template` is regenerated on every deploy and derives its own root
  via `BASH_SOURCE` — never hand-edit a release's `env.sh`, and never add a
  path placeholder to the template. Per-account values belong in the site
  file, not here.
- Every release's `daq`, `analysis`, `scripts`, and `etc` checkouts are on a
  **detached HEAD** at a resolved SHA. That is correct for the release's own
  pinned `etc` (read as `SLACUBE_LAYOUT`'s input). It is *not* the config
  archive: `SLACUBE_GIT_DIR` in the site file points at the separate,
  shared, branch-checked-out `/data/slacube/config-archive`, so `slacube cfg
  archive` (`bin/slacube:708-709`) always commits onto a real branch, never
  into a release's detached checkout.
- A release is sealed `chmod -R a-w` after build. This is load-bearing, not
  cosmetic — the store is setgid `neutrino` and a typical developer `umask`
  of `0002` would otherwise leave a running release writable by the shifter
  account.

## Known gaps, filed rather than fixed here

- `issue-001` — `analysis/slacube/trk.py` needs `scikit-learn`/`scipy`,
  neither of which is in this lock or in production; its only caller
  (`analyze_trk.py`) is not invoked by `bin/slacube` (D12).
- `issue-002` — production's `etc` config archive was 5 commits ahead of
  `origin/main` on GitHub before this tool's one-time setup step made it
  pushable for the first time (D8).
- `task-001` — the developer's `workdir` should move off the store's
  filesystem tier onto per-account NVMe; out of scope for the deploy tool
  itself.
