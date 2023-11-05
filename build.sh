#!/bin/bash

mkdir -p build

magelang compile nes -o build/nes.wasm

mkdir -p build/platform/web
rm -rf build/platform/web/*
cp ./platform/web/index.html ./build/platform/web/index.html
cp ./platform/web/main.js ./build/platform/web/main.js
cp ./build/nes.wasm ./build/platform/web/nes.wasm
