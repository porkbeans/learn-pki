#!/usr/bin/env bash

BASE_DIR="$(realpath "$(dirname "$0")")"

#
# Import common script
#
# shellcheck disable=SC1091
. "${BASE_DIR}/lib.sh"

#
# Generate certificate
#
gen_certificate "${@}"
