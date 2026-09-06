# Forward+ evidence

Read [FORWARD_PLUS.md](../../FORWARD_PLUS.md) for the baseline disclosure, feature choices, machine, matched views and measured limits.

- `baseline-manifest.json`: fingerprint of the preserved newer 3D iteration. It already selected Forward+; repository main still contained the older 2D game.
- `final-source-manifest.json`: source used for the final captures and performance recordings; final desktop export remains pending.
- `matched/`: unretouched 1280×720 baseline/final PNGs and exact frame-300 gameplay/camera metadata for seasons 1, 6 and 8.
- `performance/`: fresh-process 30-second active-play samples, 0.5-second OS RSS observations, launch commands and process inventories. Mean GPU time and invalid texture counters are null.
- `experiments/`: first failed comparison, rejected-feature trial captures and raw preliminary measurements. These are not the final comparable benchmark; some trial windows cross defeat and sequential RSS retains earlier allocations.
- `reproduction/`: disposable measurement/capture session sources. They do not assert outcomes or drive an adaptive player. Paths reflect the verification machine; adapt the source/snapshot paths when reproducing.
- `preservation.md`: focused source comparison with the newer 3D iteration.
- `rendering-review.md`: independent shader/source and matched-image critique, including the initial rejection and corrected findings. The renderer-enforcement portion authored by that reviewer is explicitly excluded from its independent verdict and checked by the runtime reviewer.

The enclosing `evidence/.gdignore` excludes these documents and capture helpers from game imports and exports. Earlier 2D and 3D evidence remains historical; none is silently presented as verification of the final migration.
