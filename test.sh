#!/bin/bash

mkdir -p build/tests/

magelang compile tests/cpu -o build/tests/cpu.wasm
wasmtime build/tests/cpu.wasm

echo Running nestest
magelang compile tests/nestest -o build/tests/nestest.wasm
wasmtime build/tests/nestest.wasm > ./build/tests/nestest.log
diff --color ./build/tests/nestest.log ./tests/nestest_stripped.log | head

