function orbit(name, radiusX, radiusY) {
  const path = `M${120 + radiusX} 90a${radiusX} ${radiusY} 0 1 1 ${-radiusX * 2} 0a${radiusX} ${radiusY} 0 1 1 ${radiusX * 2} 0Z`;
  return `<g class="landing-orbit landing-orbit-${name}" style="--electron-path: path('${path}')"><ellipse class="landing-track" cx="120" cy="90" rx="${radiusX}" ry="${radiusY}"/><path class="landing-trail" d="${path}" pathLength="100"/><g class="landing-electron"><circle class="landing-electron-glow" r="7"/><circle class="landing-electron-dot" r="2.6"/></g></g>`;
}

export function createLanding({ root }) {
  let frame;
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
  function view() {
    return `<main class="home-scroll scroll-area landing-scroll"><div class="landing" aria-hidden="true"><div class="landing-spark"><span class="landing-glow"></span><svg class="landing-mark" viewBox="0 0 240 180" fill="none" aria-hidden="true">${orbit("one", 64, 23)}${orbit("two", 61, 25)}${orbit("three", 57, 22)}<circle class="landing-core-halo" cx="120" cy="90" r="20"/><circle class="landing-core" cx="120" cy="90" r="6"/></svg></div></div></main>`;
  }
  root.addEventListener("pointermove", (event) => {
    const spark = event.target.closest(".landing-spark");
    if (!spark || reducedMotion.matches) return;
    const bounds = spark.getBoundingClientRect();
    const x = (event.clientX - bounds.left) / bounds.width - 0.5;
    const y = (event.clientY - bounds.top) / bounds.height - 0.5;
    cancelAnimationFrame(frame);
    frame = requestAnimationFrame(() => {
      spark.style.setProperty("--spark-x", `${x * 18}px`);
      spark.style.setProperty("--spark-y", `${y * 14}px`);
    });
  });
  root.addEventListener("pointerout", (event) => {
    const spark = event.target.closest(".landing-spark");
    if (spark && !spark.contains(event.relatedTarget)) {
      cancelAnimationFrame(frame);
      spark.style.removeProperty("--spark-x");
      spark.style.removeProperty("--spark-y");
    }
  });
  return { view };
}
