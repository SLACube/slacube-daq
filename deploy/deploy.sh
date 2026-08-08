#!/usr/bin/env bash
# Round 1 deploy tool for the SLACube DAQ stack.
#
# Builds one immutable, self-contained release under a shared store
# (default /opt/slacube). Never touches /home/slacube, never writes
# workdir/queue/config-archive/dropbox state, and never promotes -- it
# prints the `ln -sfn` command and stops. See
# docs/specs/2026/08/2026-08-08-1009-shared-release-store-daq-deploy-spec.md
# in the slacube workspace for the full design (D1-D15).
#
# Usage:
#   deploy.sh --config deploy/targets/slacube-dev.conf [overrides...]
#   deploy.sh --from-manifest <release>/manifest.json [overrides...]
#   deploy.sh --config <conf> --dev --name NAME [--worktree REPO=PATH ...]
#
# Overrides (all optional; each replaces the matching --config value):
#   --store DIR                 release store root
#   --ref REPO=BRANCH|TAG|SHA   one of: daq, analysis, scripts, etc
#   --python PATH               interpreter used to build the release venv
#   --ext-src DIR                source dir for vendored fzf/mdcat
#   --dropbox PATH              dropbox this release's banner will report
#   --pacman-addr HOST          recorded in manifest + banner only (D10)
#   --keep N                    releases to retain (D14)
#   --dev                       build under <store>/dev/<user>/<name> instead
#                               of <store>/releases; unsealed, never promotable
#   --name NAME                 dev release name (required with --dev)
#   --worktree REPO=PATH        dev only: symlink REPO to a local worktree
#                               instead of exporting a resolved ref; manifest
#                               is marked "dirty" and records `git describe`

set -euo pipefail

SELF="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS=(daq analysis scripts etc)
DEV_MODE=0
DEV_NAME=""

log()  { printf '[deploy] %s\n' "$*" >&2; }
die()  { printf '[deploy] ERROR: %s\n' "$*" >&2; exit 1; }

# ============================================================
# parse_args
# ============================================================
CONFIG=""
FROM_MANIFEST=""
declare -A REF_OVERRIDE=()
declare -A WORKTREE_OVERRIDE=()
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)        CONFIG="$2"; shift 2 ;;
      --from-manifest)  FROM_MANIFEST="$2"; shift 2 ;;
      --store)          OVR_STORE="$2"; shift 2 ;;
      --python)         OVR_PYTHON="$2"; shift 2 ;;
      --ext-src)        OVR_EXT_SRC="$2"; shift 2 ;;
      --dropbox)        OVR_DROPBOX="$2"; shift 2 ;;
      --pacman-addr)    OVR_PACMAN_ADDR="$2"; shift 2 ;;
      --keep)           OVR_KEEP="$2"; shift 2 ;;
      --dev)            DEV_MODE=1; shift ;;
      --name)           DEV_NAME="$2"; shift 2 ;;
      --ref)
        local kv="$2" repo val
        repo="${kv%%=*}"; val="${kv#*=}"
        [[ "$repo" != "$kv" ]] || die "--ref must be REPO=REF, got '$kv'"
        case " ${REPOS[*]} " in
          *" $repo "*) ;;
          *) die "unknown --ref repo '$repo'; expected one of: ${REPOS[*]}" ;;
        esac
        REF_OVERRIDE["$repo"]="$val"
        shift 2
        ;;
      --worktree)
        local kv="$2" repo val
        repo="${kv%%=*}"; val="${kv#*=}"
        [[ "$repo" != "$kv" ]] || die "--worktree must be REPO=PATH, got '$kv'"
        case " ${REPOS[*]} " in
          *" $repo "*) ;;
          *) die "unknown --worktree repo '$repo'; expected one of: ${REPOS[*]}" ;;
        esac
        [[ -d "$val" ]] || die "--worktree path not a directory: $val"
        WORKTREE_OVERRIDE["$repo"]="$(cd -P "$val" && pwd)"
        shift 2
        ;;
      *) die "unknown argument '$1'" ;;
    esac
  done

  [[ -n "$CONFIG" || -n "$FROM_MANIFEST" ]] \
    || die "--config or --from-manifest is required"

  if [[ ${#WORKTREE_OVERRIDE[@]} -gt 0 && "$DEV_MODE" -ne 1 ]]; then
    die "--worktree requires --dev"
  fi
  if [[ "$DEV_MODE" -eq 1 && -z "$DEV_NAME" ]]; then
    die "--dev requires --name NAME"
  fi

  if [[ -n "$CONFIG" ]]; then
    [[ -f "$CONFIG" ]] || die "config file not found: $CONFIG"
    # shellcheck source=/dev/null
    source "$CONFIG"
  fi


  if [[ -n "$FROM_MANIFEST" ]]; then
    [[ -f "$FROM_MANIFEST" ]] || die "manifest not found: $FROM_MANIFEST"
    for repo in "${REPOS[@]}"; do
      [[ -n "${REF_OVERRIDE[$repo]:-}" ]] && continue
      local sha
      sha="$(python3 -c "
import json,sys
m=json.load(open('$FROM_MANIFEST'))
print(m['refs']['$repo']['sha'])
")"
      REF_OVERRIDE["$repo"]="$sha"
    done
  fi

  STORE="${OVR_STORE:-${STORE:-}}"
  PYTHON="${OVR_PYTHON:-${PYTHON:-}}"
  EXT_SRC="${OVR_EXT_SRC:-${EXT_SRC:-}}"
  DROPBOX="${OVR_DROPBOX:-${DROPBOX:-}}"
  PACMAN_ADDR="${OVR_PACMAN_ADDR:-${PACMAN_ADDR:-}}"
  KEEP="${OVR_KEEP:-${KEEP:-}}"

  for repo in "${REPOS[@]}"; do
    local var="REF_${repo^^}"
    if [[ -n "${REF_OVERRIDE[$repo]:-}" ]]; then
      printf -v "$var" '%s' "${REF_OVERRIDE[$repo]}"
    fi
  done

  local missing=()
  [[ -n "${STORE:-}" ]]       || missing+=(STORE)
  [[ -n "${PYTHON:-}" ]]      || missing+=(PYTHON)
  [[ -n "${EXT_SRC:-}" ]]     || missing+=(EXT_SRC)
  [[ -n "${DROPBOX:-}" ]]     || missing+=(DROPBOX)
  [[ -n "${PACMAN_ADDR:-}" ]] || missing+=(PACMAN_ADDR)
  [[ -n "${KEEP:-}" ]]        || missing+=(KEEP)
  for repo in "${REPOS[@]}"; do
    [[ -n "${WORKTREE_OVERRIDE[$repo]:-}" ]] && continue
    local var="REF_${repo^^}" rvar="REMOTE_${repo^^}"
    [[ -n "${!var:-}" ]]  || missing+=("$var")
    [[ -n "${!rvar:-}" ]] || missing+=("$rvar")
  done
  [[ ${#missing[@]} -eq 0 ]] \
    || die "missing required config value(s): ${missing[*]}"
}

# ============================================================
# guard (D10) -- runs before any side effect
# ============================================================
guard() {
  local resolved
  resolved="$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$DROPBOX" 2>/dev/null || echo "$DROPBOX")"
  if [[ "$resolved" == "/data/slacube/dropbox" ]]; then
    die "refusing to deploy against the live production dropbox (/data/slacube/dropbox). Use /data/slacube/dropbox_test. There is no override flag."
  fi

  local store_resolved
  store_resolved="$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$STORE" 2>/dev/null || echo "$STORE")"
  case "$store_resolved" in
    /home/slacube|/home/slacube/*)
      die "refusing to write under /home/slacube (store resolves to $store_resolved)" ;;
  esac
  case "$resolved" in
    /home/slacube|/home/slacube/*)
      die "refusing to write under /home/slacube (dropbox resolves to $resolved)" ;;
  esac
}

# ============================================================
# preflight (D11)
# ============================================================
preflight() {
  local bin
  for bin in git nq; do
    command -v "$bin" >/dev/null 2>&1 || die "required system binary not found: $bin"
  done
  [[ -x "$PYTHON" ]] || die "python interpreter not found or not executable: $PYTHON"

  [[ -d "$EXT_SRC" ]] || die "--ext-src not a directory: $EXT_SRC"
  for bin in fzf mdcat; do
    [[ -x "${EXT_SRC}/${bin}" ]] \
      || die "required binary '$bin' not found in EXT_SRC ($EXT_SRC); every interactive slacube subcommand depends on it"
  done

  command -v uv >/dev/null 2>&1 || die "uv not found on PATH; required to build the release venv (D6)"
}

# ============================================================
# resolve_refs (D7)
# ============================================================
declare -A RESOLVED_SHA=()

resolve_refs() {
  mkdir -p "${STORE}/.cache"
  local repo ref remote sha cache
  for repo in "${REPOS[@]}"; do
    if [[ -n "${WORKTREE_OVERRIDE[$repo]:-}" ]]; then
      RESOLVED_SHA["$repo"]="worktree"
      continue
    fi
    local rvar="REMOTE_${repo^^}" fvar="REF_${repo^^}"
    remote="${!rvar}"
    ref="${!fvar}"
    cache="${STORE}/.cache/${repo}.git"
    if [[ ! -d "$cache" ]]; then
      log "seeding local mirror for $repo"
      git init -q --bare "$cache"
      git -C "$cache" remote add origin "$remote"
    fi
    # Best-effort: updates the mirror from origin. Allowed to fail so a
    # branch that exists only in this local mirror (e.g. pushed straight
    # into the cache for WIP -- Loop A) still resolves below.
    git -C "$cache" fetch -q origin "$ref" 2>/dev/null || true
    if [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then
      sha="$ref"
      git -C "$cache" cat-file -e "${sha}^{commit}" 2>/dev/null \
        || die "sha '$sha' not found for repo '$repo' (origin fetch failed and it is not already in ${cache})"
    else
      sha="$(git -C "$cache" rev-parse -q --verify FETCH_HEAD 2>/dev/null || true)"
      [[ -n "$sha" ]] || sha="$(git -C "$cache" rev-parse -q --verify "refs/heads/${ref}" 2>/dev/null || true)"
      [[ -n "$sha" ]] || sha="$(git -C "$cache" rev-parse -q --verify "refs/tags/${ref}" 2>/dev/null || true)"
      [[ -n "$sha" ]] || die "could not resolve ref '$ref' for repo '$repo' against $remote (not on origin, not already in ${cache})"
    fi
    RESOLVED_SHA["$repo"]="$sha"
    log "resolved $repo $ref -> $sha"
  done
}

# ============================================================
# build_release
# ============================================================
RELEASE_DIR=""
RELEASE_ID=""
declare -A EXT_SHA256=()

build_release() {
  if [[ "$DEV_MODE" -eq 1 ]]; then
    RELEASE_ID="dev-${USER}-${DEV_NAME}"
    RELEASE_DIR="${STORE}/dev/${USER}/${DEV_NAME}"
    if [[ -e "$RELEASE_DIR" ]]; then
      log "dev release exists, rebuilding in place: $RELEASE_DIR"
      find "$RELEASE_DIR" -type d -exec chmod u+w {} + 2>/dev/null || true
      rm -rf "$RELEASE_DIR"
    fi
  else
    local ts daq_short
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    daq_short="${RESOLVED_SHA[daq]:0:7}"
    RELEASE_ID="${ts}-${daq_short}"
    RELEASE_DIR="${STORE}/releases/${RELEASE_ID}"
    [[ -e "$RELEASE_DIR" ]] && die "release directory already exists: $RELEASE_DIR"
  fi

  mkdir -p "$RELEASE_DIR"

  local repo dest cache
  for repo in "${REPOS[@]}"; do
    dest="${RELEASE_DIR}/${repo}"
    if [[ -n "${WORKTREE_OVERRIDE[$repo]:-}" ]]; then
      log "linking $repo -> ${WORKTREE_OVERRIDE[$repo]} (dev, dirty)"
      ln -s "${WORKTREE_OVERRIDE[$repo]}" "$dest"
      continue
    fi
    cache="${STORE}/.cache/${repo}.git"
    mkdir -p "$dest"
    log "exporting $repo @ ${RESOLVED_SHA[$repo]} (no .git -- pinned input, see D8)"
    if [[ "$repo" == "scripts" ]]; then
      # firmware/ is not referenced by any deployed daq/analysis/scripts
      # code path (verified 2026-08-08); excluding it saves ~187 MB/release.
      git -C "$cache" archive "${RESOLVED_SHA[$repo]}" \
        | tar -x -C "$dest" --exclude='firmware'
    else
      git -C "$cache" archive "${RESOLVED_SHA[$repo]}" | tar -x -C "$dest"
    fi
  done

  mkdir -p "${RELEASE_DIR}/ext"
  local bin
  for bin in fzf mdcat; do
    [[ -x "${EXT_SRC}/${bin}" ]] || die "required binary '$bin' not found in EXT_SRC ($EXT_SRC)"
    cp -a "${EXT_SRC}/${bin}" "${RELEASE_DIR}/ext/${bin}"
    EXT_SHA256["$bin"]="$(sha256sum "${EXT_SRC}/${bin}" | awk '{print $1}')"
  done
  # uv is a build tool, not a runtime dependency of the deployed stack (D6);
  # it is deliberately not vendored into ext/ or put on the release PATH.

  log "building venv with $PYTHON (--link-mode=copy: a release must not hold hardlinks into a developer's ~/.cache/uv, or sealing/pruning one release can silently un-seal another)"
  uv venv --python "$PYTHON" "${RELEASE_DIR}/venv"
  uv pip sync "${SELF}/requirements-py38.txt" --python "${RELEASE_DIR}/venv/bin/python" --link-mode=copy
}

# ============================================================
# render_env (D4)
# ============================================================
render_env() {
  cp "${SELF}/env.sh.template" "${RELEASE_DIR}/env.sh"
  chmod +x "${RELEASE_DIR}/env.sh"
}

# ============================================================
# write_manifest (D7)
# ============================================================
write_manifest() {
  local deploy_sha lock_hash freeze py_version repo
  deploy_sha="$(git -C "$SELF" rev-parse HEAD 2>/dev/null || echo unknown)"
  lock_hash="$(sha256sum "${SELF}/requirements-py38.txt" | awk '{print $1}')"
  freeze="$(uv pip freeze --python "${RELEASE_DIR}/venv/bin/python" 2>/dev/null || true)"
  py_version="$("${RELEASE_DIR}/venv/bin/python" -V 2>&1)"

  {
    printf '{\n'
    printf '  "release_id": "%s",\n' "$RELEASE_ID"
    printf '  "timestamp_utc": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "dirty": %s,\n' "$([[ $DEV_MODE -eq 1 ]] && echo true || echo false)"
    printf '  "deploy_sh_sha": "%s",\n' "$deploy_sha"
    printf '  "lock_sha256": "%s",\n' "$lock_hash"
    printf '  "venv_link_mode": "copy",\n'
    printf '  "python_version": "%s",\n' "$py_version"
    printf '  "python_path": "%s",\n' "$PYTHON"
    printf '  "invocation_args": "%s",\n' "$(printf '%s ' "${ORIGINAL_ARGS[@]}" | sed 's/ $//' | sed 's/"/\\"/g')"
    printf '  "refs": {\n'
    local i=0
    for repo in "${REPOS[@]}"; do
      i=$((i+1))
      if [[ -n "${WORKTREE_OVERRIDE[$repo]:-}" ]]; then
        local wdesc
        wdesc="$(git -C "${WORKTREE_OVERRIDE[$repo]}" describe --always --dirty 2>/dev/null || echo unknown)"
        printf '    "%s": {"worktree": "%s", "describe": "%s"}%s\n' \
          "$repo" "${WORKTREE_OVERRIDE[$repo]}" "$wdesc" \
          "$([[ $i -lt ${#REPOS[@]} ]] && echo , )"
      else
        local rvar_req="REF_${repo^^}"
        printf '    "%s": {"requested": "%s", "sha": "%s"}%s\n' \
          "$repo" "${!rvar_req}" "${RESOLVED_SHA[$repo]}" \
          "$([[ $i -lt ${#REPOS[@]} ]] && echo , )"
      fi
    done
    printf '  },\n'
    printf '  "scripts_firmware_excluded": true,\n'
    printf '  "ext": {"fzf_sha256": "%s", "mdcat_sha256": "%s", "source": "%s"},\n' \
      "${EXT_SHA256[fzf]:-}" "${EXT_SHA256[mdcat]:-}" "$EXT_SRC"
    printf '  "pip_freeze": %s\n' "$(printf '%s' "$freeze" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().splitlines()))')"
    printf '}\n'
  } > "${RELEASE_DIR}/manifest.json"
}

# ============================================================
# seal_release (D3)
# ============================================================
seal_release() {
  if [[ "$DEV_MODE" -eq 1 ]]; then
    log "dev release: not sealed (D3 does not apply under ${STORE}/dev)"
    return 0
  fi
  chmod -R a-w "$RELEASE_DIR"
}

# ============================================================
# prune (D14)
# ============================================================
prune() {
  [[ "$DEV_MODE" -eq 1 ]] && return 0
  local keep="$KEEP"
  local releases_dir="${STORE}/releases"
  [[ -d "$releases_dir" ]] || return 0

  local current_target=""
  if [[ -L "${STORE}/current" ]]; then
    current_target="$(readlink -f "${STORE}/current")"
  fi

  local -A protected=()
  [[ -n "$current_target" ]] && protected["$current_target"]=1

  local f target
  for f in "$HOME"/*.sh /home/slacube/*.sh; do
    [[ -f "$f" ]] || continue
    target="$(grep -oE 'SLACUBE_RELEASE=[^ ]+' "$f" 2>/dev/null | head -1 | cut -d= -f2 || true)"
    [[ -n "$target" ]] || continue
    target="$(readlink -f "$target" 2>/dev/null || echo "$target")"
    protected["$target"]=1
  done

  local all=()
  while IFS= read -r -d '' d; do all+=("$d"); done \
    < <(find "$releases_dir" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

  local n="${#all[@]}"
  [[ "$n" -le "$keep" ]] && return 0

  local to_remove=$((n - keep))
  local removed=0 d
  for d in "${all[@]}"; do
    [[ "$removed" -ge "$to_remove" ]] && break
    [[ -n "${protected[$d]:-}" ]] && { log "prune: keeping protected release $d"; continue; }
    log "prune: removing $d"
    # Directories only: deletion needs write on the containing directory,
    # not on the files themselves. A blanket `chmod -R u+w` here previously
    # reached into files hardlinked from another (still-live) sealed
    # release's venv via uv's cache and un-sealed it. --link-mode=copy
    # (see build_release) makes this defensive; this keeps it that way.
    find "$d" -type d -exec chmod u+w {} +
    rm -rf "$d"
    removed=$((removed+1))
  done
}

# ============================================================
# main
# ============================================================
main() {
  ORIGINAL_ARGS=("$@")
  parse_args "$@"
  guard
  preflight
  resolve_refs
  build_release
  render_env
  write_manifest
  seal_release
  prune

  log "=== summary ==="
  log "release: ${RELEASE_DIR}"
  for repo in "${REPOS[@]}"; do
    log "  ${repo}: ${RESOLVED_SHA[$repo]}"
  done
  log "python: $("${RELEASE_DIR}/venv/bin/python" -V 2>&1)"
  log ""
  if [[ "$DEV_MODE" -eq 1 ]]; then
    log "dev release (unsealed, not promotable): ${RELEASE_DIR}"
    log "point a personal site file's SLACUBE_RELEASE at it directly."
  else
    log "to use this release directly, add to a site file:"
    log "  SLACUBE_RELEASE=${RELEASE_DIR}"
    log ""
    log "to promote (NOT executed by this script):"
    log "  ln -sfn ${RELEASE_DIR} ${STORE}/current"
  fi
}

main "$@"
