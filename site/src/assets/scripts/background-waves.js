const canvas = document.querySelector("[data-wave-canvas]");
const postsSection = document.querySelector(".posts-section");
const pageShell = document.querySelector(".page-shell");

if (canvas) {
  const ctx = canvas.getContext("2d");
  const prefersReducedMotion = window.matchMedia(
    "(prefers-reduced-motion: reduce)",
  ).matches;

  const wave = {
    startX: 0.98,
    startY: 0.02,
    endX: 0.78,
    endY: 0.94,
    alpha: 0.2,
    lineWidth: 2.1,
    speed: 0.000032,
    amplitude: 0.022,
    frequency: 3.0,
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

  function resolveGuideX(width) {
    const guideValue = Number.parseFloat(
      getComputedStyle(document.documentElement).getPropertyValue("--guide-left"),
    );
    if (Number.isFinite(guideValue)) {
      return guideValue;
    }
    return wave.endX * width;
  }

  function resolveEndPoint(width, height) {
    if (!postsSection) {
      return {
        endX: wave.endX * width,
        endY: wave.endY * height,
      };
    }

    const guideX = resolveGuideX(width);
    const shellLeft = pageShell?.getBoundingClientRect().left ?? 0;
    const postsTop =
      postsSection.getBoundingClientRect().top + window.scrollY;

    return {
      endX: Math.max(guideX + shellLeft, width * 0.22),
      endY: Math.min(postsTop + 2, wave.endY * height),
    };
  }

  function drawWave(width, height, time) {
    const phase = prefersReducedMotion ? 0 : time * wave.speed;
    const startX = wave.startX * width;
    const startY = wave.startY * height;
    const { endX, endY } = resolveEndPoint(width, height);
    const deltaX = endX - startX;
    const deltaY = endY - startY;
    const normalX = -deltaY;
    const normalY = deltaX;
    const normalLength = Math.hypot(normalX, normalY) || 1;
    const offsetX = (normalX / normalLength) * (wave.amplitude * height);
    const offsetY = (normalY / normalLength) * (wave.amplitude * height);
    const segments = 96;

    const gradient = ctx.createLinearGradient(startX, startY, endX, endY);
    gradient.addColorStop(0, "rgba(255, 255, 255, 0)");
    gradient.addColorStop(0.1, `rgba(${wave.color}, ${wave.alpha * 0.48})`);
    gradient.addColorStop(0.4, `rgba(${wave.color}, ${wave.alpha})`);
    gradient.addColorStop(0.72, `rgba(${wave.color}, ${wave.alpha * 0.72})`);
    gradient.addColorStop(0.92, `rgba(${wave.color}, ${wave.alpha * 0.28})`);
    gradient.addColorStop(1, "rgba(255, 255, 255, 0)");

    ctx.beginPath();
    for (let index = 0; index <= segments; index += 1) {
      const progress = index / segments;
      const x = startX + deltaX * progress;
      const y = startY + deltaY * progress;
      const envelope = Math.sin(Math.PI * progress);
      const waveOffset =
        Math.sin(progress * Math.PI * 2 * wave.frequency + phase) * envelope;
      const pointX = x + offsetX * waveOffset;
      const pointY = y + offsetY * waveOffset;

      if (index === 0) {
        ctx.moveTo(pointX, pointY);
      } else {
        ctx.lineTo(pointX, pointY);
      }
    }

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
