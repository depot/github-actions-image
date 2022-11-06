#!/bin/bash -e

# Install runner software

mkdir -p /home/runner/runners
mkdir -p /home/runner/work

cd /home/runner/runners
mkdir "$RUNNER_VERSION"
cd "$RUNNER_VERSION"

arch="x64"
case $(uname -m) in
  "x86_64")
    arch="x64"
    ;;
  "aarch64")
    arch="arm64"
    ;;
  *)
    echo "Unsupported architecture: $(uname -m)"
    exit 1
    ;;
esac

curl -O -L "https://github.com/actions/runner/releases/download/v$RUNNER_VERSION/actions-runner-linux-$arch-$RUNNER_VERSION.tar.gz"
tar xzf "./actions-runner-linux-$arch-$RUNNER_VERSION.tar.gz"
rm "./actions-runner-linux-$arch-$RUNNER_VERSION.tar.gz"
