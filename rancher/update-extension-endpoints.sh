#!/usr/bin/env bash

usage() {
  echo "Usage: $0 -o <organization> -r <repository> [<options>] <main_directory>"
  echo " options:"
  echo "  [-b | --branch] <name>           Specify the destination branch to rebuild the asset endpoints (defaults to 'gh-pages')"
  exit 1
}

BRANCH="gh-pages"
REPO=""
ORG=""

# Check if the number of arguments is less than 4
if [ $# -lt 4 ]; then
  usage
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    -b|--branch)
      if [[ -z $2 || $2 == -* ]]; then
        echo "Error: Missing argument for $1 option"
        usage
      fi
      BRANCH="${2}"
      shift 2
      ;;
    -r|--repository)
      if [[ -z $2 || $2 == -* ]]; then
        echo "Error: Missing argument for $1 option"
        usage
      fi
      REPO="${2}"
      shift 2
      ;;
    -o|--org)
      if [[ -z $2 || $2 == -* ]]; then
        echo "Error: Missing argument for $1 option"
        usage
      fi
      ORG="${2}"
      shift 2
      ;;
    *)
      MAIN_DIR="$1"
      shift
      ;;
  esac
done

if [ -z "$MAIN_DIR" ]; then
  echo "Error: Main directory not provided."
  exit 1
fi

if [ -z "$ORG" ]; then
  echo "Error: Organization not provided."
  usage
fi

if [ -z "$REPO" ]; then
  echo "Error: Repository not provided."
  usage
fi

if [ ! -d "$MAIN_DIR/charts" ]; then
  echo "Error: 'charts' directory not found in the specified main directory."
  exit 1
fi

pushd $MAIN_DIR

TMP=tmp
rm -rf ${TMP}
mkdir -p ${TMP}

HELM_INDEX="index.yaml"
CHART_TMP=${TMP}/_charts

# Usage: update_package <chart_dir> <chart_name>
function update_package() {
  local chart_dir=$1
  local chart_name=$2
  local version=$(basename "$1")

  echo "      + Patching Helm chart for: ${chart_name} version: ${version}"

  CR_FILE=${chart_dir}/templates/cr.yaml
  ENDPOINT=https://raw.githubusercontent.com/${ORG}/${REPO}/${BRANCH}/extensions/${chart_name}/${version}
  sed -i.bak -e 's@endpoint:.*@endpoint: '"$ENDPOINT"'@' ${CR_FILE}
  rm -f ${CR_FILE}.bak

  CHART_FILE="${chart_dir}/Chart.yaml"
  ICON_FILE=$(grep -oP '(?<=icon: ).*' "$CHART_FILE" | grep -oP '(?<=assets/).*')
  ICON="https://raw.githubusercontent.com/${ORG}/${REPO}/main/pkg/${chart_name}/assets/${ICON_FILE}"
  sed -i.bak -e 's@icon:.*@icon: '"$ICON"'@' "$CHART_FILE"
  rm -f "${CHART_FILE}.bak"

  helm package "$version_dir" -d "./assets/$chart_name" --version "$version"
}

# Usage: update_index <chart_dir> <chart_name>
function update_index() {
  local chart_dir=$1
  local chart_name=$2
  local version=$(basename "$1")

  echo "      + Updating Helm index for: ${chart_name} version: ${version}"

  if [ -f "${HELM_INDEX}" ]; then
    local UPDATE="--merge ${HELM_INDEX}"
  fi

  # Base URL referencing assets directly from GitHub
  local BASE_URL="assets/${chart_name}"

  rm -rf ${CHART_TMP}
  mkdir -p ${CHART_TMP}
  cp assets/${chart_name}/${chart_name}-${version}.tgz ${CHART_TMP}

  helm repo index ${CHART_TMP} --url ${BASE_URL} ${UPDATE}

  cp ${CHART_TMP}/index.yaml ${HELM_INDEX}
}

function main() {
  for chart_dir in "./charts"/*; do
    if [ -d "$chart_dir" ]; then
      chart_name=$(basename "$chart_dir")

      # Find all version directories within the chart directory and repackage the charts for each
      for version_dir in "$chart_dir"/*; do
        if [ -d "$version_dir" ]; then

          update_package "${version_dir}" "${chart_name}"
          update_index "${version_dir}" "${chart_name}"
        fi
      done
    fi
  done

  rm -rf ${TMP}

  echo -e "Repackaging completed."
}

main

popd
