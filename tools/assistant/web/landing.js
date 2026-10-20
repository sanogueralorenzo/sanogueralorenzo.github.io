function orbit(name, radiusX, radiusY) {
  const path = `M${120 + radiusX} 90a${radiusX} ${radiusY} 0 1 1 ${-radiusX * 2} 0a${radiusX} ${radiusY} 0 1 1 ${radiusX * 2} 0Z`;
  return `<g class="landing-orbit landing-orbit-${name}" style="--electron-path: path('${path}')"><ellipse class="landing-track" cx="120" cy="90" rx="${radiusX}" ry="${radiusY}"/><path class="landing-trail" d="${path}" pathLength="100"/><g class="landing-electron"><circle class="landing-electron-glow" r="7"/><circle class="landing-electron-dot" r="2.6"/></g></g>`;
}

export function createLanding() {
  function view() {
    return `<main class="home-scroll scroll-area landing-scroll"><div class="landing" aria-hidden="true"><div class="landing-spark"><span class="landing-glow"></span><svg class="landing-mark" viewBox="0 0 240 180" preserveAspectRatio="none" fill="none" aria-hidden="true">${orbit("one", 64, 23)}${orbit("two", 61, 25)}${orbit("three", 57, 22)}<circle class="landing-core-halo" cx="120" cy="90" r="20"/><circle class="landing-core" cx="120" cy="90" r="6"/></svg></div></div></main>`;
  }
  return { view };
}
