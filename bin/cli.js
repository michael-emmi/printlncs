#!/usr/bin/env node
"use strict";

let meow = require('meow');
let printlncs = require('../lib/index');

let cli = meow(`
  Usage
    $ printlncs PDF

  Options
    --scale FACTOR        Scale by FACTOR.
    --paper SIZE          Set paper SIZE (letter, a4)
    --padding SPACE       Add SPACE points padding to bounding boxes
    --bottom SPACE        Add SPACE points to bottom margin
    --between SPACE       Add SPACE points between pages
    --key-pages PAGES     Calculate bounding boxes on PAGES.

  Examples
    $ printlncs main.pdf
`, {
  default: {
    scale: undefined,
    paper: 'letter',
    padding: 10,
    bottom: 0,
    between: 0,
    keyPages: '[1,2,3,4,5]'
  }
});

(async () => {
  cli.input.length == 1 || cli.showHelp();
  console.log(`${cli.pkg.name} version ${cli.pkg.version}`);
  let out = await printlncs(Object.assign({}, cli.flags, {input: cli.input[0]}));
  console.log(`generated ${out}`);
})();
