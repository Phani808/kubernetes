#!/usr/bin/env bash

# Copyright 2017 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset
set -o pipefail

# The root of the build/dist directory
KUBE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "${KUBE_ROOT}/hack/lib/init.sh"

# Generates $1/api.pb.go from the protobuf file $1/api.proto
# and formats it correctly
# $1: Full path to the directory where the api.proto file is
function kube::protoc::generate_proto() {
  kube::golang::setup_env
  GO111MODULE=on GOPROXY=off go install k8s.io/code-generator/cmd/go-to-protobuf/protoc-gen-gogo

  kube::protoc::check_protoc

  local package=${1}
  kube::protoc::protoc "${package}"
  kube::protoc::format "${package}"
}

# Checks that the current protoc version is at least version 3.0.0-beta1
# exit 1 if it's not the case
function kube::protoc::check_protoc() {
  if [[ -z "$(which protoc)" || "$(protoc --version)" != "libprotoc 3."* ]]; then
    echo "Generating protobuf requires protoc 3.0.0-beta1 or newer. Please download and"
    echo "install the platform appropriate Protobuf package for your OS: "
    echo
    echo "  https://github.com/protocolbuffers/protobuf/releases"
    echo
    echo "WARNING: Protobuf changes are not being validated"
    exit 1
  fi
}

# Generates $1/api.pb.go from the protobuf file $1/api.proto
# $1: Full path to the directory where the api.proto file is
function kube::protoc::protoc() {
  local package=${1}
  gogopath=$(dirname "$(kube::util::find-binary "protoc-gen-gogo")")

  (
    cd "${package}"

    # This invocation of --gogo_out produces its output in the current
    # directory (despite gogo docs saying it would be source-relative, it
    # isn't).  The inputs to this function do not all have a common root, so
    # this works best for all inputs.
    PATH="${gogopath}:${PATH}" protoc \
      --proto_path="$(pwd -P)" \
      --proto_path="${KUBE_ROOT}/vendor" \
      --gogo_out=paths=source_relative,plugins=grpc:. \
      api.proto
  )
}

# Formats $1/api.pb.go, adds the boilerplate comments and run gofmt on it
# $1: Full path to the directory where the api.proto file is
function kube::protoc::format() {
  local package=${1}

  # Update boilerplate for the generated file.
  cat hack/boilerplate/boilerplate.generatego.txt "${package}/api.pb.go" > tmpfile && mv tmpfile "${package}/api.pb.go"

  # Run gofmt to clean up the generated code.
  kube::golang::verify_go_version
  gofmt -s -w "${package}/api.pb.go"
}

# Compares the contents of $1 and $2
# Echo's $3 in case of error and exits 1
function kube::protoc::diff() {
  local ret=0
  diff -I "gzipped FileDescriptorProto" -I "0x" -Naupr "${1}" "${2}" || ret=$?
  if [[ ${ret} -ne 0 ]]; then
    echo "${3}"
    exit 1
  fi
}
