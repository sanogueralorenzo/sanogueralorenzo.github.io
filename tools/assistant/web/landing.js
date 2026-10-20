export function createLanding() {
  function view() {
    return `<main class="home-scroll scroll-area landing-scroll"><div class="landing" aria-hidden="true"><div class="landing-spark"><span class="landing-glow"></span><svg class="landing-mark" viewBox="0 0 240 180" preserveAspectRatio="none" fill="none" aria-hidden="true"><circle class="landing-core-halo" cx="120" cy="90" r="22"/><circle class="landing-core" cx="120" cy="90" r="10"/></svg></div></div></main>`;
  }
  return { view };
}
