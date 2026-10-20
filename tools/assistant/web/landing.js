export function createLanding() {
  function view() {
    return `<main class="home-scroll scroll-area landing-scroll"><div class="landing" aria-hidden="true"><div class="landing-spark"><span class="landing-glow"></span><div class="landing-mark"><span class="landing-core-halo"></span><span class="landing-core"></span></div></div></div></main>`;
  }
  return { view };
}
