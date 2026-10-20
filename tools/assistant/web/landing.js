import { escapeHTML, icon } from "./view.js";

const starters = [
  { label: "Think it through", symbol: "sparkle", prompt: "I have an idea I'd like to think through. Help me explore it and find a good next step." },
  { label: "Make a plan", symbol: "check", prompt: "Help me turn what I need to do into a clear, realistic plan. Start by asking what's on my plate." },
  { label: "Build something", symbol: "plus", prompt: "I'd like to build something. Help me shape the idea and figure out where to start." },
];

export function createLanding({ root, composer }) {
  let nextStarter = Math.floor(Math.random() * starters.length);
  let frame;
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
  const prompts = document.createElement("nav");
  prompts.className = "landing-prompts";
  prompts.setAttribute("aria-label", "Starting points");
  prompts.innerHTML = starters.map((starter, index) => `<button type="button" data-action="landing-start" data-starter="${index}">${icon(starter.symbol, 14)}<span>${escapeHTML(starter.label)}</span></button>`).join("");
  composer.element.append(prompts);

  function view() {
    return `<main class="home-scroll scroll-area landing-scroll"><section class="landing" aria-labelledby="landing-title"><button class="landing-spark" type="button" data-action="landing-inspire" aria-label="Give me a starting point" title="Give me a starting point"><span class="landing-glow"></span><svg class="landing-mark" viewBox="0 0 240 180" fill="none" aria-hidden="true"><g class="landing-orbit landing-orbit-one"><ellipse cx="120" cy="90" rx="81" ry="29"/><circle class="landing-satellite" cx="201" cy="90" r="3"/></g><g class="landing-orbit landing-orbit-two"><ellipse cx="120" cy="90" rx="68" ry="32"/><circle class="landing-satellite" cx="52" cy="90" r="2.5"/></g><g class="landing-orbit landing-orbit-three"><ellipse cx="120" cy="90" rx="60" ry="28"/></g><circle class="landing-core-halo" cx="120" cy="90" r="20"/><circle class="landing-core" cx="120" cy="90" r="6"/></svg><span class="landing-spark-hint">A little inspiration</span></button><h1 id="landing-title">Start with a <em>spark.</em></h1><p>A question, a project, a half-formed idea.<br>Let’s see where it goes.</p></section></main>`;
  }
  function sync(visible) { prompts.hidden = !visible; }
  function handleClick(button) {
    let index;
    if (button.dataset.action === "landing-inspire") index = nextStarter++ % starters.length;
    else if (button.dataset.action === "landing-start") index = Number(button.dataset.starter);
    else return false;
    if (starters[index]) composer.startPrompt(starters[index].prompt);
    return true;
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
  return { view, sync, handleClick };
}
