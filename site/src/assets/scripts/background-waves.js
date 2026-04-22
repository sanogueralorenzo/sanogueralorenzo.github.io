const canvas = document.querySelector("[data-wave-canvas]");

if (canvas) {
  const ctx = canvas.getContext("2d");
  const prefersReducedMotion = window.matchMedia(
    "(prefers-reduced-motion: reduce)",
  ).matches;

  const waveSets = [
    {
      startX: 0.36,
      endX: 0.94,
      baseY: 0.18,
      amplitude: 0.055,
      frequency: 1.6,
      lineWidth: 1.15,
      alpha: 0.16,
      speed: 0.00008,
      color: "38, 44, 56",
    },
    {
      startX: 0.48,
      endX: 0.96,
      baseY: 0.29,
      amplitude: 0.042,
      frequency: 2.3,
      lineWidth: 0.9,
      alpha: 0.11,
      speed: -0.00005,
      color: "62, 78, 96",
    },
    {
      startX: 0.08,
      endX: 0.46,
      baseY: 0.7,
      amplitude: 0.048,
      frequency: 1.9,
      lineWidth: 0.95,
      alpha: 0.12,
      speed: 0.00006,
      color: "50, 58, 70",
    },
    {
      startX: 0.22,
      endX: 0.72,
      baseY: 0.86,
      amplitude: 0.04,
      frequency: 2.0,
      lineWidth: 0.85,
      alpha: 0.09,
      speed: -0.00004,
      color: "76, 88, 104",
    },
  ];

  const mistForms = [
    { x: 0.78, y: 0.22, width: 0.24, height: 0.11, alpha: 0.065 },
    { x: 0.69, y: 0.58, width: 0.18, height: 0.08, alpha: 0.045 },
    { x: 0.24, y: 0.74, width: 0.24, height: 0.1, alpha: 0.035 },
  ];

  function resizeCanvas() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const width = window.innerWidth;
    const height = Math.max(window.innerHeight, document.body.scrollHeight);

    canvas.width = Math.floor(width * dpr);
    canvas.height = Math.floor(height * dpr);
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;

    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  function drawMist(width, height) {
    ctx.save();
    ctx.filter = "blur(26px)";

    for (const form of mistForms) {
      const gradient = ctx.createRadialGradient(
        form.x * width,
        form.y * height,
        0,
        form.x * width,
        form.y * height,
        form.width * width,
      );

      gradient.addColorStop(0, `rgba(74, 86, 102, ${form.alpha})`);
      gradient.addColorStop(0.5, `rgba(74, 86, 102, ${form.alpha * 0.35})`);
      gradient.addColorStop(1, "rgba(74, 86, 102, 0)");

      ctx.fillStyle = gradient;
      ctx.beginPath();
      ctx.ellipse(
        form.x * width,
        form.y * height,
        form.width * width,
        form.height * height,
        -0.3,
        0,
        Math.PI * 2,
      );
      ctx.fill();
    }

    ctx.restore();
  }

  function drawWave(set, width, height, time) {
    const startX = set.startX * width;
    const endX = set.endX * width;
    const baseY = set.baseY * height;
    const amplitude = set.amplitude * height;
    const length = endX - startX;
    const phase = prefersReducedMotion ? 0 : time * set.speed;
    const segments = 72;

    ctx.beginPath();
    for (let index = 0; index <= segments; index += 1) {
      const progress = index / segments;
      const x = startX + length * progress;
      const envelope = Math.sin(Math.PI * progress);
      const y =
        baseY +
        Math.sin(progress * Math.PI * 2 * set.frequency + phase) *
          amplitude *
          envelope;

      if (index === 0) {
        ctx.moveTo(x, y);
      } else {
        ctx.lineTo(x, y);
      }
    }

    const gradient = ctx.createLinearGradient(startX, baseY, endX, baseY);
    gradient.addColorStop(0, "rgba(255, 255, 255, 0)");
    gradient.addColorStop(0.16, `rgba(${set.color}, ${set.alpha * 0.55})`);
    gradient.addColorStop(0.52, `rgba(${set.color}, ${set.alpha})`);
    gradient.addColorStop(0.84, `rgba(${set.color}, ${set.alpha * 0.38})`);
    gradient.addColorStop(1, "rgba(255, 255, 255, 0)");

    ctx.strokeStyle = gradient;
    ctx.lineWidth = set.lineWidth;
    ctx.stroke();
  }

  function draw(time = 0) {
    const width = canvas.clientWidth;
    const height = canvas.clientHeight;

    ctx.clearRect(0, 0, width, height);
    drawMist(width, height);

    for (const wave of waveSets) {
      drawWave(wave, width, height, time);
    }
  }

  function frame(time) {
    draw(time);
    if (!prefersReducedMotion) {
      window.requestAnimationFrame(frame);
    }
  }

  resizeCanvas();
  draw();

  window.addEventListener("resize", () => {
    resizeCanvas();
    draw();
  });

  if (!prefersReducedMotion) {
    window.requestAnimationFrame(frame);
  }
}
