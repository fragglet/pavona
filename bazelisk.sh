#!/usr/bin/env bash
# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# This is a wrapper script for `bazelisk` that downloads and executes bazelisk.
# Bazelisk is a wrapper for `bazel` that can download and execute the project's
# required bazel version.

set -euo pipefail

# Change to this script's directory, as it is the location of the bazel workspace.
cd "$(dirname "$0")"

: "${CURL_FLAGS:=--silent}"
: "${REPO_TOP:=$(git rev-parse --show-toplevel)}"
: "${REPO_TOP:=$(dirname $0)}"
: "${BINDIR:=.bin}"
: "${BAZEL_BIN:=$(which bazel 2>/dev/null)}"

# Bazelisk (not Bazel) release. Keep this in sync with `util/container/Dockerfile`.
readonly release="v1.24.1"
declare -A hashes=(
    # sha256sums for v1.24.1.  Update this if you update the release.
    [linux-amd64]="0aee09c71828b0012750cb9b689ce3575da8e230f265bf8d6dcd454eee6ea842"
    [linux-arm64]="2a0e5d397f7ddbdac1deff4167c7681d9d1d025c5dfa979c2b37f091f032d01a"
)

declare -A architectures=(
    # Map `uname -m -o` to bazelisk's precompiled binary target names.
    [aarch64 GNU/Linux]="linux-arm64"
    [x86_64 GNU/Linux]="linux-amd64"
)

function os_arch() {
    local arch
    arch="$(uname -m -o)"
    echo "${architectures[$arch]:-${arch}}"
}

function check_hash() {
    local file target
    file="$1"
    target="$(os_arch)"
    echo "${hashes[$target]}  $file" | sha256sum --check --quiet
}

function prepare() {
    local target
    target="$(os_arch)"
    local bindir="${REPO_TOP}/${BINDIR}"
    local file="${bindir}/bazelisk"
    local url="https://github.com/bazelbuild/bazelisk/releases/download/${release}/bazelisk-${target}"

    mkdir -p "$bindir"
    echo "Downloading bazelisk ${release} (${url})." >> $bindir/bazelisk.log
    curl ${CURL_FLAGS} --location "$url" --output "$file"
    chmod +x "$file"
}

function up_to_date() {
    local file="$1"
    # We need an update if the file doesn't exist or it has the wrong hash
    test -f "$file" || return 1
    check_hash "$file" || return 1
    return 0
}

function main() {
    local bindir="${REPO_TOP}/${BINDIR}"
    local file="${BAZEL_BIN:-${bindir}/bazelisk}"
    local lockfile="${bindir}/bazelisk.lock"

    # If the user has Bazel in their PATH, check its version.
    # Fallback to bazelisk if it doesn't match.
    if [ -x "$BAZEL_BIN" ]; then
        if [ "$("$BAZEL_BIN" --version)" != "bazel $(cat .bazelversion)" ]; then
            file="${bindir}/bazelisk"
        fi
    fi

    # Are we using bazel from the user's PATH or using bazelisk?
    if expr match "${file}" ".*bazelisk$" >/dev/null; then
        if ! up_to_date "$file"; then
            # Grab the lock, blocking until success. Upon success, check again
            # whether we're up to date (because some other process might have
            # downloaded bazelisk in the meantime). If not, download it ourselves.
            mkdir -p "$bindir"
            (flock -x 9; up_to_date "$file" || prepare) 9>>"$lockfile"
        fi
        if ! check_hash "$file"; then
            echo "sha256sum doesn't match expected value"
            exit 1
        fi
    fi

    exec "$file" "$@"
}

main "$@"
