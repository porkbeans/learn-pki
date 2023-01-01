#!/usr/bin/env bash

BASE_DIR="$(realpath "$(dirname "$0")")"
PKI_BASE_DIR="${BASE_DIR}/data"

get_ca_dir() {
  echo "${PKI_BASE_DIR}/CA/$1"
}

init_ca_dir() {
  local CA_DIR="$1"

  local CA_CERT_DIR="${CA_DIR}/certs"
  local CA_SERIAL="${CA_DIR}/ca.srl"
  local CA_DATABASE="${CA_DIR}/index.txt"

  mkdir -p "${CA_DIR}"
  mkdir -p "${CA_CERT_DIR}"

  if [ ! -f "${CA_SERIAL}" ]; then
    echo 02 >"${CA_SERIAL}"
  fi

  if [ ! -f "${CA_DATABASE}" ]; then
    touch "${CA_DATABASE}"
  fi
}

check_if_expired_in_90days() {
  CERTIFICATE="$1"

  openssl x509 -in "${CERTIFICATE}" -noout -checkend "$((90 * 24 * 3600))"
  return "$?"
}

gen_ca_root() {
  # shellcheck disable=SC2155
  local ROOT_CA_DIR="$(get_ca_dir root)"
  local ROOT_CA_CONFIG="${BASE_DIR}/config/req_root_ca.cnf"
  local ROOT_CA_PRIVATE_KEY="${ROOT_CA_DIR}/ca.key"
  local ROOT_CA_CERTIFICATE="${ROOT_CA_DIR}/ca.crt"
  local ROOT_CA_SUBJECT="/O=Example/CN=Example Root CA"
  local ROOT_CA_VALID_DAYS=3650

  init_ca_dir "${ROOT_CA_DIR}"

  if [ ! -f "${ROOT_CA_PRIVATE_KEY}" ]; then
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "${ROOT_CA_PRIVATE_KEY}"
  fi

  if [ ! -f "${ROOT_CA_CERTIFICATE}" ] || ! check_if_expired_in_90days "${ROOT_CA_CERTIFICATE}"; then
    openssl req \
      -x509 \
      -batch \
      -config "${ROOT_CA_CONFIG}" \
      -subj "${ROOT_CA_SUBJECT}" \
      -days "${ROOT_CA_VALID_DAYS}" \
      -key "${ROOT_CA_PRIVATE_KEY}" \
      -nodes \
      -out "${ROOT_CA_CERTIFICATE}"
  fi
}

gen_ca_intermediate() {
  local CA_ID="$1"
  local CA_NAME="$2"

  local CA_CONFIG="${BASE_DIR}/config/ca.cnf"
  local CA_EXT_FILE="${BASE_DIR}/config/ext_root.cnf"

  # shellcheck disable=SC2155
  local CA_DIR="$(get_ca_dir "${CA_ID}")"
  local CA_PRIVATE_KEY="${CA_DIR}/ca.key"
  local CA_CERTIFICATE_REQUEST="${CA_DIR}/ca.csr"
  local CA_CERTIFICATE="${CA_DIR}/ca.crt"
  local CA_CERTIFICATE_FULLCHAIN="${CA_DIR}/ca.fullchain.crt"
  local CA_SUBJECT="/O=Example/CN=Example ${CA_NAME} CA"
  local CA_VALID_DAYS=3650

  # shellcheck disable=SC2155
  local ROOT_CA_DIR="$(get_ca_dir root)"
  local ROOT_CA_CERTIFICATE="${ROOT_CA_DIR}/ca.crt"

  init_ca_dir "${CA_DIR}"

  if [ ! -f "${CA_PRIVATE_KEY}" ]; then
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "${CA_PRIVATE_KEY}"
  fi

  if [ ! -f "${CA_CERTIFICATE}" ] || ! check_if_expired_in_90days "${CA_CERTIFICATE}"; then
    openssl req \
      -batch \
      -subj "${CA_SUBJECT}" \
      -key "${CA_PRIVATE_KEY}" \
      -nodes \
      -sha512 \
      -new \
      -out "${CA_CERTIFICATE_REQUEST}"

    OPENSSL_CA_NAME=root openssl ca \
      -batch \
      -config "${CA_CONFIG}" \
      -extfile "${CA_EXT_FILE}" \
      -extensions 'v3_ext' \
      -days "${CA_VALID_DAYS}" \
      -in "${CA_CERTIFICATE_REQUEST}" \
      -out "${CA_CERTIFICATE}" \
      -notext
    cat "${CA_CERTIFICATE}" "${ROOT_CA_CERTIFICATE}" >"${CA_CERTIFICATE_FULLCHAIN}"
    rm -f "${CA_CERTIFICATE_REQUEST}"
  fi
}

gen_certificate() {
  local CA_ID="$1"
  local COMMON_NAME="$2"
  shift 2

  local EXT_SANS=""
  while getopts 'd:i:e:' OPT; do
    local SAN
    case "${OPT}" in
    d) SAN="DNS:${OPTARG}" ;;
    i) SAN="IP:${OPTARG}" ;;
    e) SAN="email:${OPTARG}" ;;
    *)
      echo "ERROR: unknown option: -${OPT}"
      exit 1
      ;;
    esac

    if [ -z "${EXT_SANS}" ]; then
      EXT_SANS="subjectAltName=${SAN}"
    else
      EXT_SANS="${EXT_SANS},${SAN}"
    fi
  done

  local CA_CONFIG="${BASE_DIR}/config/ca.cnf"
  local CA_EXT_FILE="${BASE_DIR}/config/ext_${CA_ID}.cnf"

  local CERT_DIR="${PKI_BASE_DIR}/certs/${CA_ID}"
  # shellcheck disable=SC2155
  local BASE_NAME="$(echo "${COMMON_NAME}" | sed -e 's/\*/wildcard/' -e 's/\./_/g')"

  local PRIVATE_KEY="${CERT_DIR}/${BASE_NAME}.key"
  local CERTIFICATE_REQUEST="${CERT_DIR}/${BASE_NAME}.csr"
  local CERTIFICATE="${CERT_DIR}/${BASE_NAME}.crt"
  local CERTIFICATE_FULLCHAIN="${CERT_DIR}/${BASE_NAME}.fullchain.crt"

  local VALID_DAYS=365
  local SUBJECT="/O=Example/CN=${COMMON_NAME}"
  local OPT_EXT_SANS=()
  if [ -n "${EXT_SANS}" ]; then
    OPT_EXT_SANS+=("-addext" "${EXT_SANS}")
  fi

  # shellcheck disable=SC2155
  local CA_DIR="$(get_ca_dir "${CA_ID}")"
  local CA_CERTIFICATE_FULLCHAIN="${CA_DIR}/ca.fullchain.crt"

  mkdir -p "${CERT_DIR}"

  if [ ! -f "${PRIVATE_KEY}" ]; then
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "${PRIVATE_KEY}"
  fi

  if [ ! -f "${CERTIFICATE}" ] || ! check_if_expired_in_90days "${CERTIFICATE}"; then
    openssl req \
      -batch \
      -subj "${SUBJECT}" \
      "${OPT_EXT_SANS[@]}" \
      -key "${PRIVATE_KEY}" \
      -nodes \
      -sha512 \
      -new \
      -out "${CERTIFICATE_REQUEST}"
    OPENSSL_CA_NAME="${CA_ID}" openssl ca \
      -batch \
      -config "${CA_CONFIG}" \
      -extfile "${CA_EXT_FILE}" \
      -extensions 'v3_ext' \
      -days "${VALID_DAYS}" \
      -in "${CERTIFICATE_REQUEST}" \
      -out "${CERTIFICATE}" \
      -notext

    cat "${CERTIFICATE}" "${CA_CERTIFICATE_FULLCHAIN}" >"${CERTIFICATE_FULLCHAIN}"
    rm -f "${CERTIFICATE_REQUEST}"
  fi
}
