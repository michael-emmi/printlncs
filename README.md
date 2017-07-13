## printlncs

Save paper by printing every two pages of [LNCS][] proceedings on a single page,
without scaling, if possible.

# Requirements

* [Node.js][]
* [Poppler][] providing `pdftops` executable
* [Ghostscript][]
* [pstopdf][]
* [TeX][] providing `pstops` and `psselect` executables

# Installation

    $ npm i -g printlncs

# Usage

    $ printlncs

# Development

Emulate installation of local repository:

    $ npm link

Release a new version to npm:

    $ npm version [major|minor|patch]
    $ npm publish

[Node.js]: https://nodejs.org
[Poppler]: https://poppler.freedesktop.org
[Ghostscript]: https://www.ghostscript.com
[pstopdf]: https://developer.apple.com/legacy/library/documentation/Darwin/Reference/ManPages/man1/pstopdf.1.html
[Tex]: https://www.tug.org
[LNCS]: http://www.springer.com/gp/computer-science/lncs
