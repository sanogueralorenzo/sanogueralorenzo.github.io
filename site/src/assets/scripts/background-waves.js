const canvas = document.querySelector("[data-wave-canvas]");
const postsSection = document.querySelector(".posts-section");

if (canvas) {
  const ctx = canvas.getContext("2d");
  const prefersReducedMotion = window.matchMedia(
    "(prefers-reduced-motion: reduce)",
  ).matches;

  const wave = {
    startX: 0.98,
    startY: 0.02,
    c1x: 0.94,
    c1y: 0.12,
    c2x: 0.7,
    c2y: 0.26,
    c3x: 0.9,
    c3y: 0.42,
    c4x: 0.58,
    c4y: 0.6,
    c5x: 0.86,
    c5y: 0.76,
    c6x: 0.64,
    c6y: 0.88,
    endX: 0.8,
    endY: 0.94,
    alpha: 0.2,
    lineWidth: 2.1,
    speed: 0.00004,
    swingX: 0.024,
    swingY: 0.028,
    color: "58, 72, 92",
  };

  const offshoots = [
    {
      anchor: 0.2,
      c1x: -0.02,
      c1y: 0.04,
      c2x: -0.1,
      c2y: 0.14,
      endX: -0.16,
      endY: 0.24,
      alpha: 0.11,
      lineWidth: 1.1,
    },
    {
      anchor: 0.48,
      c1x: -0.03,
      c1y: 0.05,
      c2x: -0.08,
      c2y: 0.12,
      endX: -0.12,
      endY: 0.2,
      alpha: 0.09,
      lineWidth: 0.95,
    },
    {
      anchor: 0.72,
      c1x: -0.015,
      c1y: 0.04,
      c2x: -0.06,
      c2y: 0.1,
      endX: -0.1,
      endY: 0.17,
      alpha: 0.08,
      lineWidth: 0.85,
    },
  ];

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

  function clampEndY(height) {
    if (!postsSection) {
      return wave.endY * height;
    }

    const postsTop =
      postsSection.getBoundingClientRect().top + window.scrollY;
    return Math.min(wave.endY * height, postsTop - 48);
  }

  function cubicPoint(t, p0, p1, p2, p3) {
    const inv = 1 - t;
    return (
      inv ** 3 * p0 +
      3 * inv ** 2 * t * p1 +
      3 * inv * t ** 2 * p2 +
      t ** 3 * p3
    );
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
    const endY = clampEndY(height);

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

    const midX = (p2x + p3x) / 2;
    const midY = (p2y + p3y) / 2;

    return {
      startX,
      startY,
      p1x,
      p1y,
      p2x,
      p2y,
      midX,
      midY,
      p3x,
      p3y,
      p4x,
      p4y,
      endX,
      endY,
    };
  }

  function drawOffshoots(points, width) {
    for (const offshoot of offshoots) {
      const { anchor } = offshoot;
      let baseX;
      let baseY;
      let tangentX;
      let tangentY;

      if (anchor <= 0.5) {
        const localT = anchor / 0.5;
        baseX = cubicPoint(
          localT,
          points.startX,
          points.p1x,
          points.p2x,
          points.midX,
        );
        baseY = cubicPoint(
          localT,
          points.startY,
          points.p1y,
          points.p2y,
          points.midY,
        );
        tangentX = points.midX - points.p2x;
        tangentY = points.midY - points.p2y;
      } else {
        const localT = (anchor - 0.5) / 0.5;
        baseX = cubicPoint(
          localT,
          points.midX,
          points.p3x,
          points.p4x,
          points.endX,
        );
        baseY = cubicPoint(
          localT,
          points.midY,
          points.p3y,
          points.p4y,
          points.endY,
        );
        tangentX = points.endX - points.p4x;
        tangentY = points.endY - points.p4y;
      }

      const normalX = -tangentY || -1;
      const normalY = tangentX || 0;
      const normalLength = Math.hypot(normalX, normalY) || 1;
      const dirX = normalX / normalLength;
      const dirY = normalY / normalLength;

      const c1x = baseX + width * (offshoot.c1x * dirX);
      const c1y = baseY + width * (offshoot.c1y * dirY);
      const c2x = baseX + width * (offshoot.c2x * dirX);
      const c2y = baseY + width * (offshoot.c2y * dirY);
      const endX = baseX + width * (offshoot.endX * dirX);
      const endY = baseY + width * (offshoot.endY * dirY);

      const gradient = ctx.createLinearGradient(baseX, baseY, endX, endY);
      gradient.addColorStop(0, `rgba(${wave.color}, ${offshoot.alpha})`);
      gradient.addColorStop(0.72, `rgba(${wave.color}, ${offshoot.alpha * 0.34})`);
      gradient.addColorStop(1, "rgba(255, 255, 255, 0)");

      ctx.beginPath();
      ctx.moveTo(baseX, baseY);
      ctx.bezierCurveTo(c1x, c1y, c2x, c2y, endX, endY);
      ctx.strokeStyle = gradient;
      ctx.lineWidth = offshoot.lineWidth;
      ctx.lineCap = "round";
      ctx.stroke();
    }
  }

  function draw(time = 0) {
    const width = canvas.clientWidth;
    const height = canvas.clientHeight;

    ctx.clearRect(0, 0, width, height);
    drawMist(width, height);
    const points = drawWave(width, height, time);
    drawOffshoots(points, width);
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
