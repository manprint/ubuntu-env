#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    exec "$@"
fi

target_user="ubuntu"
target_uid="$(id -u "$target_user")"

if [[ -n "${GRANT_PERMISSION:-}" ]]; then
    IFS=',' read -ra _ids <<< "$GRANT_PERMISSION"
    for raw in "${_ids[@]}"; do
        gid="${raw//[[:space:]]/}"
        [[ -z "$gid" ]] && continue
        if ! [[ "$gid" =~ ^[0-9]+$ ]]; then
            echo "[entrypoint] skip non-numeric '$gid'" >&2
            continue
        fi
        if [[ "$gid" == "0" || "$gid" == "$target_uid" ]]; then
            continue
        fi
        if existing="$(getent group "$gid")"; then
            gname="${existing%%:*}"
        else
            gname="hostgrp_${gid}"
            groupadd -g "$gid" "$gname"
        fi
        if ! id -nG "$target_user" | tr ' ' '\n' | grep -qx "$gname"; then
            usermod -aG "$gname" "$target_user"
        fi
    done
fi

if [[ -n "${GIT_USER:-}" ]]; then
    runuser -u "$target_user" -- git config --global user.name "$GIT_USER"
    HOME=/root git config --global user.name "$GIT_USER"
fi
if [[ -n "${GIT_MAIL:-}" ]]; then
    runuser -u "$target_user" -- git config --global user.email "$GIT_MAIL"
    HOME=/root git config --global user.email "$GIT_MAIL"
fi

umask "${WORKSPACE_UMASK:-002}"

if [[ $# -eq 0 ]]; then
    set -- /bin/bash
fi

exec runuser -u "$target_user" -- "$@"
