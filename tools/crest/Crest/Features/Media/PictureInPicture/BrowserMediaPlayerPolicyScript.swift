import Foundation

enum BrowserMediaPlayerPolicyScript {
    static let source = #"""
          const parentOf = element => element.parentElement || element.getRootNode()?.host;
          const isDecorative = video => {
            for (let element = video; element; element = parentOf(element)) {
              const style = getComputedStyle(element);
              if (element.hidden || element.inert || element.getAttribute('aria-hidden') === 'true'
                  || ['presentation', 'none'].includes(element.getAttribute('role'))
                  || style.display === 'none' || style.visibility !== 'visible'
                  || Number(style.opacity) === 0 || style.pointerEvents === 'none') return true;
            }
            return false;
          };
          const hasPlayerControls = (video, wasInteracted = false) => {
            if (video.controls) return true;
            const videoArea = video.getBoundingClientRect().width * video.getBoundingClientRect().height;
            let container = parentOf(video);
            for (let depth = 0; container && depth < 6; depth++, container = parentOf(container)) {
              if (container === document.body || container === document.documentElement) break;
              const bounds = container.getBoundingClientRect();
              if (bounds.width * bounds.height > Math.max(videoArea * 6, 4000000)) break;
              // A lone "pause background animation" control is deliberately not a
              // player. Seek/volume sliders plus transport buttons identify a real
              // control surface without depending on the language of its labels.
              const exposed = control => {
                for (let element = control; element && element !== container; element = parentOf(element)) {
                  if (element.hidden || getComputedStyle(element).display === 'none') return false;
                }
                return true;
              };
              const buttons = Array.from(container.querySelectorAll('button, [role="button"]')).filter(exposed);
              const timeline = Array.from(container.querySelectorAll('input[type="range"], [role="slider"], progress')).some(exposed);
              if (buttons.length >= 2 && timeline) return true;
              // Players without a seek bar (live streams) can qualify after a real
              // click/key interaction and with multiple actual playback controls.
              if (wasInteracted && buttons.length >= 2) {
                const controls = Array.from(buttons).filter(button =>
                  /play|pause|mute|volume|fullscreen/i.test(
                    [button.getAttribute('aria-label'), button.title, button.textContent].join(' ')
                  ));
                if (controls.length >= 2) return true;
              }
            }
            return false;
          };
        """#
}
