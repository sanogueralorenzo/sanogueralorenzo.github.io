export function createLanding({ root }) {
  let frame;
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
  function view() {
    return `<main class="home-scroll scroll-area landing-scroll"><div class="landing" aria-hidden="true"><div class="landing-spark"><span class="landing-glow"></span><svg class="landing-mark" viewBox="0 0 240 180" fill="none" aria-hidden="true"><g class="landing-orbit landing-orbit-one"><ellipse cx="120" cy="90" rx="81" ry="29"/><circle class="landing-satellite" cx="201" cy="90" r="3"/></g><g class="landing-orbit landing-orbit-two"><ellipse cx="120" cy="90" rx="68" ry="32"/><circle class="landing-satellite" cx="52" cy="90" r="2.5"/></g><g class="landing-orbit landing-orbit-three"><ellipse cx="120" cy="90" rx="60" ry="28"/></g><circle class="landing-core-halo" cx="120" cy="90" r="20"/><circle class="landing-core" cx="120" cy="90" r="6"/></svg></div></div></main>`;
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
