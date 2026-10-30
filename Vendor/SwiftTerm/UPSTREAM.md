# SwiftTerm smooth-scroll demo

Vendored from https://github.com/migueldeicaza/SwiftTerm, tag v1.19.0,
commit 464df5207fc2432e16c9a23abe538187196daf5f. Original MIT license retained.

Farport patches: macOS CoreGraphics-only fractional scrollback presentation;
additional partially visible row, caret and pointer/IME coordinate alignment;
full viewport invalidation while fractional output is visible. Integer navigation,
resize and detachment reset the fraction. The buffer retains its integer yDisp;
no pixel-position persistence or transport changes. Pure position tests are included.
Metal is disabled on the first smooth scroll. iOS renderer is unchanged.

This is an experimental local fork, not an upstream release. Remote mouse-wheel
reporting remains discrete. AppKit precise deltas include native momentum; ordinary
mouse-wheel notches keep line scrolling. No synthetic animation or easing is added.
