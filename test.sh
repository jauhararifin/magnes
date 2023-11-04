#!/bin/bash

mkdir -p build/tests/

magelang compile tests/cpu -o build/tests/cpu.wasm
wasmtime build/tests/cpu.wasm
