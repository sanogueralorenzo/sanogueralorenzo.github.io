const canvas = document.querySelector("[data-wave-canvas]");

if (canvas) {
  const ctx = canvas.getContext("2d");
  const prefersReducedMotion = window.matchMedia(
    "(prefers-reduced-motion: reduce)",
  ).matches;

  const waveSets = [
    {
      startX: 0.46,
      endX: 0.98,
      baseY: 0.11,
      amplitude: 0.05,
      frequency: 1.5,
      lineWidth: 1.05,
      alpha: 0.18,
      speed: 0.000075,
      color: "40, 48, 62",
    },
    {
      startX: 0.42,
      endX: 0.96,
      baseY: 0.19,
      amplitude: 0.038,
      frequency: 1.9,
      lineWidth: 0.9,
      alpha: 0.135,
      speed: -0.000045,
      color: "68, 84, 102",
    },
    {
      startX: 0.18,
      endX: 0.84,
      baseY: 0.62,
      amplitude: 0.042,
      frequency: 1.7,
      lineWidth: 0.95,
      alpha: 0.12,
      speed: 0.000055,
      color: "48, 58, 72",
    },
    {
      startX: 0.08,
      endX: 0.66,
      baseY: 0.82,
      amplitude: 0.034,
      frequency: 1.8,
      lineWidth: 0.82,
      alpha: 0.1,
      speed: -0.000038,
      color: "74, 88, 106",
    },
    {
      startX: 0.52,
      endX: 0.98,
      baseY: 0.31,
      amplitude: 0.03,
      frequency: 2.35,
      lineWidth: 0.78,
      alpha: 0.11,
      speed: 0.000042,
      color: "86, 102, 120",
    },
    {
      startX: 0.26,
      endX: 0.92,
      baseY: 0.48,
      amplitude: 0.024,
      frequency: 2.15,
      lineWidth: 0.72,
      alpha: 0.08,
      speed: -0.00003,
      color: "88, 100, 116",
    },
  ];

  const branchSets = [
    {
      startX: 0.98,
      startY: 0.02,
      c1x: 0.9,
      c1y: 0.16,
      c2x: 0.78,
      c2y: 0.3,
      endX: 0.62,
      endY: 0.44,
      alpha: 0.12,
      lineWidth: 0.9,
      speed: 0.000045,
      swing: 0.018,
      color: "52, 64, 80",
    },
    {
      startX: 0.96,
      startY: 0.04,
      c1x: 0.9,
      c1y: 0.24,
      c2x: 0.86,
      c2y: 0.46,
      endX: 0.76,
      endY: 0.69,
      alpha: 0.1,
      lineWidth: 0.82,
      speed: -0.00004,
      swing: 0.015,
      color: "68, 84, 102",
    },
    {
      startX: 0.9,
      startY: 0.1,
      c1x: 0.86,
      c1y: 0.2,
      c2x: 0.68,
      c2y: 0.42,
      endX: 0.48,
      endY: 0.56,
      alpha: 0.09,
      lineWidth: 0.76,
      speed: 0.000032,
      swing: 0.02,
      color: "78, 94, 112",
    },
  ];

  const mistForms = [
    { x: 0.84, y: 0.16, width: 0.28, height: 0.12, alpha: 0.075 },
    { x: 0.7, y: 0.38, width: 0.22, height: 0.09, alpha: 0.05 },
    { x: 0.62, y: 0.67, width: 0.21, height: 0.08, alpha: 0.04 },
    { x: 0.28, y: 0.76, width: 0.26, height: 0.1, alpha: 0.032 },
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

  function drawBranch(set, width, height, time) {
    const phase = prefersReducedMotion ? 0 : time * set.speed;
    const swing = Math.sin(phase) * set.swing * width;
    const sway = Math.cos(phase * 0.8) * set.swing * height * 0.34;

    const startX = set.startX * width;
    const startY = set.startY * height;
    const c1x = set.c1x * width + swing;
    const c1y = set.c1y * height + sway;
    const c2x = set.c2x * width - swing * 0.8;
    const c2y = set.c2y * height + sway * 0.7;
    const endX = set.endX * width - swing * 0.55;
    const endY = set.endY * height + sway * 0.55;

    const gradient = ctx.createLinearGradient(startX, startY, endX, endY);
    gradient.addColorStop(0, "rgba(255, 255, 255, 0)");
    gradient.addColorStop(0.12, `rgba(${set.color}, ${set.alpha * 0.4})`);
    gradient.addColorStop(0.5, `rgba(${set.color}, ${set.alpha})`);
    gradient.addColorStop(0.82, `rgba(${set.color}, ${set.alpha * 0.34})`);
    gradient.addColorStop(1, "rgba(255, 255, 255, 0)");

    ctx.beginPath();
    ctx.moveTo(startX, startY);
    ctx.bezierCurveTo(c1x, c1y, c2x, c2y, endX, endY);
    ctx.strokeStyle = gradient;
    ctx.lineWidth = set.lineWidth;
    ctx.stroke();
  }

  function draw(time = 0) {
    const width = canvas.clientWidth;
    const height = canvas.clientHeight;

    ctx.clearRect(0, 0, width, height);
    drawMist(width, height);

    for (const branch of branchSets) {
      drawBranch(branch, width, height, time);
    }

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
