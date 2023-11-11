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

  nametable1Ctx = nametable1.getContext('2d')
  nametable1Ctx.webkitImageSmoothingEnabled = false
  nametable1Ctx.mozImageSmoothingEnabled = false
  nametable1Ctx.imageSmoothingEnabled = false

  nametable2Ctx = nametable2.getContext('2d')
  nametable2Ctx.webkitImageSmoothingEnabled = false
  nametable2Ctx.mozImageSmoothingEnabled = false
  nametable2Ctx.imageSmoothingEnabled = false

  nametable3Ctx = nametable3.getContext('2d')
  nametable3Ctx.webkitImageSmoothingEnabled = false
  nametable3Ctx.mozImageSmoothingEnabled = false
  nametable3Ctx.imageSmoothingEnabled = false

  nametable4Ctx = nametable4.getContext('2d')
  nametable4Ctx.webkitImageSmoothingEnabled = false
  nametable4Ctx.mozImageSmoothingEnabled = false
  nametable4Ctx.imageSmoothingEnabled = false

  preselectedRom.addEventListener('change', function(e) {
    romInput.disabled = e.target.value !== 'select-file'
  })

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
    getNametable1Framebuffer, getNametable2Framebuffer, getNametable3Framebuffer, getNametable4Framebuffer,
    keydownJoypad1A, keydownJoypad1B, keydownJoypad1Select, keydownJoypad1Start, keydownJoypad1Up, keydownJoypad1Down, keydownJoypad1Left, keydownJoypad1Right,
    keyupJoypad1A, keyupJoypad1B, keyupJoypad1Select, keyupJoypad1Start, keyupJoypad1Up, keyupJoypad1Down, keyupJoypad1Left, keyupJoypad1Right,
  } = module.instance.exports;
  memoryBuffer = memory.buffer

  window.setPalette = function(id) {
    setDebugPaletteId(id)
  }

  document.addEventListener('keyup', (event) => {
    const key = event.key.toLowerCase();
    if (key === 'arrowup')
      keyupJoypad1Up();
    else if (key === 'arrowright')
      keyupJoypad1Right();
    else if (key === 'arrowleft')
      keyupJoypad1Left();
    else if (key === 'arrowdown')
      keyupJoypad1Down();
    else if (key === 'x')
      keyupJoypad1A();
    else if (key === 'z')
      keyupJoypad1B();
    else if (key === 'enter')
      keyupJoypad1Start();
    else if (key === 'control')
      keyupJoypad1Select();
    else
      return

    event.preventDefault()
  });

  document.addEventListener('keydown', (event) => {
    const key = event.key.toLowerCase();
    if (key === 'arrowup')
      keydownJoypad1Up();
    else if (key === 'arrowright')
      keydownJoypad1Right();
    else if (key === 'arrowleft')
      keydownJoypad1Left();
    else if (key === 'arrowdown')
      keydownJoypad1Down();
    else if (key === 'x')
      keydownJoypad1A();
    else if (key === 'z')
      keydownJoypad1B();
    else if (key === 'enter')
      keydownJoypad1Start();
    else if (key === 'control')
      keydownJoypad1Select();
    else
      return

    event.preventDefault()
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
      const elapsed = currentTime - lastExecuted
      tick(BigInt(Math.round(elapsed)))
      lastExecuted = currentTime

      const debugTile = getDebugTileFramebufer()
      renderToCanvas(charTileCanvas, charDebugCtx, debugTile)

      const palettes = getDebugPaletteImage()
      renderToCanvas(paletteCanvas, paletteCanvasCtx, [palettes[0], 33, 1])

      const screen = getScreenFramebuffer();
      renderToCanvas(canvas, ctx, screen)

      const nametable1Image = getNametable1Framebuffer()
      renderToCanvas(nametable1, nametable1Ctx, nametable1Image)

      const nametable2Image = getNametable2Framebuffer()
      renderToCanvas(nametable2, nametable2Ctx, nametable2Image)

      const nametable3Image = getNametable3Framebuffer()
      renderToCanvas(nametable3, nametable3Ctx, nametable3Image)

      const nametable4Image = getNametable4Framebuffer()
      renderToCanvas(nametable4, nametable4Ctx, nametable4Image)
    }

    requestAnimationFrame(frame)
  }
  requestAnimationFrame(frame)

  playButton.onclick = function() {
    document.activeElement.blur()

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
        reset();
        playing = true;
        lastExecuted = performance.now();
      }
    }

    if (preselectedRom.value === 'select-file') {
      if (romInput.files.length === 0) {
        alert("Missing ROM file");
        return
      }
      const file = romInput.files[0];
      reader.readAsArrayBuffer(file);
    } else {
      fetch(preselectedRom.value).then(res => res.blob()).then(blob => {
      reader.readAsArrayBuffer(blob);
      })
    }
  }

};
