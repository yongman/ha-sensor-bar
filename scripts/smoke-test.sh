#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist .build
swiftc -parse-as-library -warnings-as-errors scripts/SmokeLauncher.swift -o .build/smoke-launcher
.build/smoke-launcher
