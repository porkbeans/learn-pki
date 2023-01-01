#!/usr/bin/env bash

BASE_DIR="$(realpath "$(dirname "$0")")"

#
# Import common script
#
# shellcheck disable=SC1091
. "${BASE_DIR}/lib.sh"

#
# Generate Root CA
#
gen_ca_root

#
# Generate Intermediate CA
#
gen_ca_intermediate server Server
gen_ca_intermediate client Client
