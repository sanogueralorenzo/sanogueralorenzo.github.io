const canvas = document.querySelector("[data-wave-canvas]");

if (canvas) {
  const ctx = canvas.getContext("2d");
  const prefersReducedMotion = window.matchMedia(
    "(prefers-reduced-motion: reduce)",
  ).matches;

  const wave = {
    startX: 0.98,
    startY: 0.02,
    c1x: 0.92,
    c1y: 0.16,
    c2x: 0.72,
    c2y: 0.34,
    c3x: 0.88,
    c3y: 0.56,
    c4x: 0.62,
    c4y: 0.78,
    endX: 0.74,
    endY: 1.02,
    alpha: 0.2,
    lineWidth: 1.8,
    speed: 0.00004,
    swingX: 0.018,
    swingY: 0.022,
    color: "58, 72, 92",
  };

  const mistForms = [
    { x: 0.84, y: 0.18, width: 0.22, height: 0.1, alpha: 0.045 },
    { x: 0.76, y: 0.48, width: 0.18, height: 0.08, alpha: 0.03 },
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
    ctx.filter = "blur(28px)";

    for (const form of mistForms) {
      const gradient = ctx.createRadialGradient(
        form.x * width,
        form.y * height,
        0,
        form.x * width,
        form.y * height,
        form.width * width,
      );

      gradient.addColorStop(0, `rgba(76, 90, 108, ${form.alpha})`);
      gradient.addColorStop(0.55, `rgba(76, 90, 108, ${form.alpha * 0.24})`);
      gradient.addColorStop(1, "rgba(76, 90, 108, 0)");

      ctx.fillStyle = gradient;
      ctx.beginPath();
      ctx.ellipse(
        form.x * width,
        form.y * height,
        form.width * width,
        form.height * height,
        -0.6,
        0,
        Math.PI * 2,
      );
      ctx.fill();
    }

    ctx.restore();
  }

  function drawWave(width, height, time) {
    const phase = prefersReducedMotion ? 0 : time * wave.speed;
    const driftX = Math.sin(phase) * wave.swingX * width;
    const driftY = Math.cos(phase * 0.8) * wave.swingY * height;

    const startX = wave.startX * width;
    const startY = wave.startY * height;

    const p1x = wave.c1x * width + driftX * 0.35;
    const p1y = wave.c1y * height + driftY * 0.24;
    const p2x = wave.c2x * width - driftX * 0.8;
    const p2y = wave.c2y * height + driftY * 0.4;

    const p3x = wave.c3x * width + driftX * 0.5;
    const p3y = wave.c3y * height - driftY * 0.2;
    const p4x = wave.c4x * width - driftX;
    const p4y = wave.c4y * height + driftY * 0.5;

    const endX = wave.endX * width + driftX * 0.28;
    const endY = wave.endY * height;

    const gradient = ctx.createLinearGradient(startX, startY, endX, endY);
    gradient.addColorStop(0, "rgba(255, 255, 255, 0)");
    gradient.addColorStop(0.1, `rgba(${wave.color}, ${wave.alpha * 0.48})`);
    gradient.addColorStop(0.4, `rgba(${wave.color}, ${wave.alpha})`);
    gradient.addColorStop(0.72, `rgba(${wave.color}, ${wave.alpha * 0.72})`);
    gradient.addColorStop(0.92, `rgba(${wave.color}, ${wave.alpha * 0.28})`);
    gradient.addColorStop(1, "rgba(255, 255, 255, 0)");

    ctx.beginPath();
    ctx.moveTo(startX, startY);
    ctx.bezierCurveTo(p1x, p1y, p2x, p2y, (p2x + p3x) / 2, (p2y + p3y) / 2);
    ctx.bezierCurveTo(p3x, p3y, p4x, p4y, endX, endY);
    ctx.strokeStyle = gradient;
    ctx.lineWidth = wave.lineWidth;
    ctx.lineCap = "round";
    ctx.stroke();
  }

  function draw(time = 0) {
    const width = canvas.clientWidth;
    const height = canvas.clientHeight;

    ctx.clearRect(0, 0, width, height);
    drawMist(width, height);
    drawWave(width, height, time);
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
