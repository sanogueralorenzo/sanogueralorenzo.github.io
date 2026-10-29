export function createLanding() {
  function view() {
    return `<main class="home-scroll scroll-area landing-scroll"><div class="landing" aria-hidden="true"><span class="landing-glow"></span><div class="landing-mark"><span class="landing-core-halo"></span><span class="landing-core"></span></div></div></main>`;
  }
  return { view };
}
