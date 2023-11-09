window.onload = async function() {
  const ctx = canvas.getContext('2d')
  ctx.webkitImageSmoothingEnabled = false;
  ctx.mozImageSmoothingEnabled = false;
  ctx.imageSmoothingEnabled = false;

  const charDebugCtx = charTileCanvas.getContext('2d')
  charDebugCtx.webkitImageSmoothingEnabled = false;
  charDebugCtx.mozImageSmoothingEnabled = false;
  charDebugCtx.imageSmoothingEnabled = false;

  paletteCanvasCtx = paletteCanvas.getContext('2d')
  paletteCanvasCtx.webkitImageSmoothingEnabled = false
  paletteCanvasCtx.mozImageSmoothingEnabled = false
  paletteCanvasCtx.imageSmoothingEnabled = false

  const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
  const data = imageData.data

  for (let i = 0; i < data.length; i += 4) {
    data[i+0] = 0
    data[i+1] = 0
    data[i+2] = 0
    data[i+3] = 255
  }

  ctx.putImageData(imageData, 0, 0)

  const resp = await fetch('/nes.wasm')
  const bytes = await resp.arrayBuffer()
  let memoryBuffer;
  let debuggingBuffer = "";
  const module = await WebAssembly.instantiate(bytes, {
    wasi_snapshot_preview1: {
      fd_write: (fd, iovec, count, result) => {
        for (let i = 0; i < count; i++) {
          const buff = new Uint32Array(memoryBuffer, iovec + 2*i, 2);
          const p = buff[0]
          const len = buff[1]

          const stringBytes = new Uint8Array(memoryBuffer, p, len);
          const text = new TextDecoder().decode(stringBytes);
          debuggingBuffer += text
          const x = debuggingBuffer.indexOf("\n");
          if (x > -1) {
            console.log(debuggingBuffer.substr(0, x))
            debuggingBuffer = debuggingBuffer.substr(x + 1)
          }
        }
      }
    },
  })
  const {
    onKeyupArrowUp, onKeydownArrowUp,
    onKeyupArrowRight, onKeydownArrowRight,
    onKeyupArrowLeft, onKeydownArrowLeft,
    onKeyupArrowDown, onKeydownArrowDown,
    tick,
    memory,
    getRom, loadRom,
    getRam,
    reset,
    getFrameBuffer,
    debugCPU,
    getDebugTileFramebufer,
    getDebugPaletteImage,
    setDebugPaletteId,
    getScreenFramebuffer,
  } = module.instance.exports;
  memoryBuffer = memory.buffer

  window.setPalette = function(id) {
    setDebugPaletteId(id)
  }

  document.addEventListener('keyup', (event) => {
    if (event.key === 'ArrowUp')
      onKeyupArrowUp();
    else if (event.key === 'ArrowRight')
      onKeyupArrowRight();
    else if (event.key === 'ArrowLeft')
      onKeyupArrowLeft();
    else if (event.key === 'ArrowDown')
      onKeyupArrowDown();
  });

  document.addEventListener('keydown', (event) => {
    if (event.key === 'ArrowUp')
      onKeydownArrowUp();
    else if (event.key === 'ArrowRight')
      onKeydownArrowRight();
    else if (event.key === 'ArrowLeft')
      onKeydownArrowLeft();
    else if (event.key === 'ArrowDown')
      onKeydownArrowDown();
  });

  function getString(offset) {
    const buff = new Uint8Array(memoryBuffer);
    let length = 0;
    while (buff[offset + length] !== 0) {
      length++;
    }
    const stringBytes = new Uint8Array(memoryBuffer, offset, length);
    const text = new TextDecoder().decode(stringBytes);
    return text
  }

  function getCPU() {
    const [a,x,y,sp,pc,status, lastOpcode, lastInsOffset, lastAddr, lastData, lastPc] = debugCPU()

    const desc = getString(lastInsOffset)

    return {
      last: desc,
      a: [a,a.toString(16)],
      x: [x,x.toString(16)],
      y: [y,y.toString(16)],
      sp: [sp,sp.toString(16)],
      pc: [pc,pc.toString(16)],
      status: [status,status.toString(2)],
      lastOpcode,
      lastAddr: [lastAddr, lastAddr.toString(16)],
      lastData: [lastData, lastData.toString(16)],
      lastPc: [lastPc, lastPc.toString(16)],
    }
  }

  function renderToCanvas(theCanvas, ctx, image) {
    const [framebuffer, width, height] = image;
    const pixels = new Uint8ClampedArray(memoryBuffer, framebuffer, width*height*4);
    const imageData = new ImageData(pixels, width, height);

    theCanvas.width = width;
    theCanvas.height = height;
    ctx.putImageData(imageData, 0, 0)
  }

  let playing = false
  let lastExecuted = Math.round(performance.now() * 1_000_000)
  function frame() {
    if (playing) {
      const currentTime = Math.round(performance.now() * 1_000_000)
      const elapsed = Math.min(currentTime - lastExecuted, 10_000_000)
      tick(BigInt(Math.round(elapsed)))
      lastExecuted = currentTime

      const debugTile = getDebugTileFramebufer()
      renderToCanvas(charTileCanvas, charDebugCtx, debugTile)

      const palettes = getDebugPaletteImage()
      renderToCanvas(paletteCanvas, paletteCanvasCtx, [palettes[0], 33, 1])

      const screen = getScreenFramebuffer();
      renderToCanvas(canvas, ctx, screen)
    }

    requestAnimationFrame(frame)
  }
  requestAnimationFrame(frame)

  playButton.onclick = function() {
    if (romInput.files.length === 0) {
      alert("Missing ROM file");
      return
    }

    const file = romInput.files[0];
    const reader = new FileReader();
    reader.onload = function(e) {
      const arrayBuffer = e.target.result;
      const byteArray = new Uint8Array(arrayBuffer);
      if (byteArray.length > 1073741824) {
        alert("ROM is too big")
        return
      }

      const offset = getRom()
      const target = new Uint8Array(memoryBuffer)
      target.set(byteArray, offset)

      const [resultIsValid, resultError] = loadRom();
      if (!resultIsValid) {
        const message = getString(resultError);
        alert(message);
      } else {
        console.log('resetting')
        reset();
        console.log("getDebugTileFramebufer", getDebugTileFramebufer())
        playing = true;
        lastExecuted = performance.now();
      }
    }
    reader.readAsArrayBuffer(file);
  }

};
