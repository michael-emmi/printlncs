#!/usr/bin/env node
"use strict";

import meow from 'meow';
import printlncs from '../lib/index.js';

let cli = meow(`
  Usage
    $ printlncs PDF

  Options
    --scale FACTOR        Scale by FACTOR.
    --paper SIZE          Set paper SIZE (letter, a4)
    --padding SPACE       Add SPACE points padding to bounding boxes
    --bottom SPACE        Add SPACE points to bottom margin
    --left SPACE          Add SPACE points to left margin
    --between SPACE       Add SPACE points between pages
    --key-pages PAGES     Calculate bounding boxes on PAGES.

  Examples
    $ printlncs main.pdf
`, {
  importMeta: import.meta,
  flags: {
    scale: {
        default: undefined
    },
    paper: {
        default: 'letter'
    },
    padding: {
        default: 10
    },
    bottom: {
        default: 0
    },
    left: {
        default: 0
    },
    between: {
        default: 0
    },
    keyPages: {
        default: '[1,2,3,4,5]'
    }
  }
});

(async () => {
  cli.input.length == 1 || cli.showHelp();
  console.log(`${cli.pkg.name} version ${cli.pkg.version}`);
  let out = await printlncs(Object.assign({}, cli.flags, {input: cli.input[0]}));
  console.log(`generated ${out}`);
})();
