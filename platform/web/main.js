window.onload = async function() {
  canvas.width = 32
  canvas.height = 32

  const ctx = canvas.getContext('2d')
  ctx.webkitImageSmoothingEnabled = false;
  ctx.mozImageSmoothingEnabled = false;
  ctx.imageSmoothingEnabled = false;

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
  const module = await WebAssembly.instantiate(bytes, {
    // TODO: remove WASI related imports
    wasi_snapshot_preview1: {
      fd_write: () => console.log('fd_write_called'),
    },
  })
  const {
    return_10,
    onKeyupArrowUp, onKeydownArrowUp,
    onKeyupArrowRight, onKeydownArrowRight,
    onKeyupArrowLeft, onKeydownArrowLeft,
    onKeyupArrowDown, onKeydownArrowDown,
    tick,
    memory,
    getRom,
    getRam,
    reset,
    getFrameBuffer,
    debugCPU,
  } = module.instance.exports;
  const memoryBuffer = memory.buffer

  document.addEventListener('keyup', (event) => {
    if (event.key === 'ArrowUp')
      onKeydownArrowUp();
    else if (event.key === 'ArrowRight')
      onKeydownArrowRight();
    else if (event.key === 'ArrowLeft')
      onKeydownArrowLeft();
    else if (event.key === 'ArrowDown')
      onKeydownArrowDown();
  });

  document.addEventListener('keydown', (event) => {
    if (event.key === 'ArrowUp')
      onKeyupArrowUp();
    else if (event.key === 'ArrowRight')
      onKeyupArrowRight();
    else if (event.key === 'ArrowLeft')
      onKeyupArrowLeft();
    else if (event.key === 'ArrowDown')
      onKeyupArrowDown();
  });

  function getCPU() {
    const [a,x,y,sp,pc,status, lastOpcode, lastInsOffset, lastAddr, lastData, lastPc] = debugCPU()

    const buff = new Uint8Array(memoryBuffer);
    let length = 0;
    while (buff[lastInsOffset + length] !== 0) {
      length++;
    }
    const stringBytes = new Uint8Array(memoryBuffer, lastInsOffset, length);
    const desc = new TextDecoder().decode(stringBytes);

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

  let playing = false
  let lastExecuted = performance.now();
  const interval = 0.07;
  function frame() {
    if (playing) {
      const currentTime = performance.now();
      // console.log({lastExecuted, currentTime})
      while ((lastExecuted + interval) <= currentTime) {
        tick()
        const x = getCPU()
        if (x.lastAddr[0] >= 0x200 && x.lastAddr[0] < 0x600)
          console.debug('CPU after', x)
        lastExecuted += interval
      }
      // console.log('-------------------------------------------------')

      const framebuffer = getFrameBuffer()
      const buff = new Uint8Array(memoryBuffer);
      for (let i = 0; i < 32*32; i++) {
        const color_map = {
          0: [0,0,0],
          1: [255,255,255],
          2: [128,128,128],
          9: [128,128,128],
          3: [255,0,0],
          10: [255,0,0],
          4: [0,255,0],
          11: [0,255,0],
          5: [0,0,255],
          12: [0,0,255],
          6: [255,0,255],
          13: [255,0,255],
          7: [0,255,255],
          14: [0,255,255],
        }
        const color = color_map[buff[framebuffer + i]] || [255,255,0];
        data[i*4+0] = color[0]
        data[i*4+1] = color[1]
        data[i*4+2] = color[2]
      }
      ctx.putImageData(imageData, 0, 0)
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
      if (byteArray.length > 40*1024) {
        alert("ROM is too big")
        return
      }
      const offset = getRom()
      const target = new Uint8Array(memoryBuffer)
      target.set(byteArray, offset)
      // console.log('jauhar', offset.toString(16), getRam().toString(16), target[getRam() + 0x600])
      reset();

      playing = true;
      lastExecuted = performance.now();
    }
    reader.readAsArrayBuffer(file);
  }

};
