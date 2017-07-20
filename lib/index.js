const debug = require('debug')('printlncs');
const assert = require('assert');
const path = require('path');
const cp = require('child_process');
const es = require('event-stream');
const tmp = require('tmp');

module.exports = print;

class Point {
  constructor(x, y) {
    this.x = x;
    this.y = y;
  }

  static zero() {
    return new Point(0,0);
  }

  add(point) {
    return new Point(this.x + point.x, this.y + point.y);
  }

  scale(factor) {
    return new Point(this.x * factor, this.y * factor);
  }

  toString() {
    return `(${this.x},${this.y})`;
  }
}

class Box {
  constructor(p1, p2) {
    assert.ok(p1.x <= p2.x);
    assert.ok(p1.y <= p2.y);
    this.p1 = p1;
    this.p2 = p2;
  }

  get top() {
    return this.p1.y;
  }

  get bottom() {
    return this.p2.y;
  }

  get left() {
    return this.p1.x;
  }

  get right() {
    return this.p2.x;
  }

  get width() {
    return this.right - this.left;
  }

  get height() {
    return this.bottom - this.top;
  }

  static zero() {
    return new Box(Point.zero(), Point.zero());
  }

  add(box) {
    return new Box(this.p1.add(box.p1), this.p2.add(box.p2));
  }

  scale(factor) {
    return new Box(this.p1.scale(factor), this.p2.scale(factor));
  }

  toString() {
    return `${this.p1}:${this.p2}`;
  }
}

function getPaperBox(args) {
  switch (args.paper) {
    case 'letter':
      return new Box(new Point(0,0), new Point(612, 792));
    case 'a4':
      return new Box(new Point(0,0), new Point(595, 842));
    default:
      throw `unexpected page type: ${args.paper}`
  }
}

async function getPageCount(args) {
  return new Promise((resolve, reject) => {
    let grep = cp.spawn('grep', ['%%Pages', args.psfile]);
    let awk = cp.spawn('awk', ['{print $2}']);
    grep.stdout.pipe(awk.stdin);
    let lines = awk.stdout.pipe(es.split());
    let count;
    lines.on('data', (data) => {
      if (count)
        return
      if (data) {
        count = +data;
        debug(`page count: ${count}`);
        resolve(count);
      }
    });
    lines.on('end', () => {
      if (!count)
        reject(`expected page count`);
    })
  });
}

async function getBoundingBox(args) {
  let pageCount = await getPageCount(args);
  let boxData = await Promise.all(JSON.parse(args.keyPages).filter(p => p <= pageCount).map(pageNum =>
    new Promise((resolve, reject) => {
      let psselect = cp.spawn('psselect', [`-p${pageNum}`, args.psfile]);
      let getbox = cp.spawn('gs', ['-sDEVICE=bbox', '-dNOPAUSE', '-dBATCH', '-']);
      psselect.stdout.pipe(getbox.stdin);
      let lines = getbox.stderr.pipe(es.split());
      let match;
      lines.on('data', (data) => {
        if (match)
          return;
        debug(`got bbox data: ${data}`);
        if (match = data.toString().match(/%%HiResBoundingBox: ([\d.]+) ([\d.]+) ([\d.]+) ([\d.]+)/))
          resolve(new Box(new Point(+match[1], +match[2]), new Point(+match[3], +match[4])));
      });
      lines.on('end', () => {
        if (!match)
          reject(`expected bounding box data`);
      });
    })
  ));
  return boxData.reduce((avg,b) => avg.add(b), Box.zero()).scale(1 / boxData.length);
}

async function composeExpr(args) {
  let paperBox = getPaperBox(args);
  let boundingBox = await getBoundingBox(args);

  if (!args.scale) {
    args.scale = Math.min(1,
      (paperBox.width - 2 * args.padding) / boundingBox.height,
      (paperBox.height - 3 * args.padding) / boundingBox.width * 2);
    if (args.scale < 1)
      console.log(`warning: scaling to ${args.scale}`);
  }

  let horizontalMargin = (paperBox.width - boundingBox.height * args.scale) / 2;
  let verticalMargin = (paperBox.height - 2 * boundingBox.width * args.scale) / 3;
  let leftPageShift = new Point(
    horizontalMargin + boundingBox.bottom * args.scale - args.bottom,
    verticalMargin - boundingBox.left * args.scale - args.between
  );
  let rightPageShift = new Point(
    leftPageShift.x,
    leftPageShift.y + verticalMargin + boundingBox.width * args.scale + 2 * args.between
  );
  debug(`paper box: ${paperBox}`);
  debug(`bounding box: ${boundingBox}`);
  debug(`scaling: ${args.scale}`);
  debug(`horizontal margin: ${horizontalMargin}`);
  debug(`vertical margin: ${verticalMargin}`);
  debug(`left-page shift: ${leftPageShift}`);
  debug(`right-page shift: ${rightPageShift}`);
  return `2:0L@${args.scale}${leftPageShift}+1L@${args.scale}${rightPageShift}`;
}

async function convertToPostscript(args) {
  debug(`generating ${args.psfile} from ${args.input}`);
  switch (path.extname(args.input)) {
    case '.pdf':
      let pdftops = cp.spawnSync('pdftops', [args.input, args.psfile]);
      if (pdftops.status || pdftops.error)
        throw `failed to generate postscript from ${args.input}`;
      break;
    default:
      throw `unexpected extension: ${path.extname(args.input)}`;
  }
}

async function composePostscript(args) {
  debug(`generating ${args.ps2up} from ${args.psfile}`);
  let expr = await composeExpr(args);
  debug(`expression: ${expr}`);
  let pstops = cp.spawnSync('pstops', [
    `-p${args.paper}`,
    expr,
    args.psfile,
    args.ps2up
  ]);
  if (pstops.status || pstops.error)
    throw `failed to compose postscript from ${args.psfile}`;
}

async function convertFromPostscript(args) {
  debug(`generating ${args.output} from ${args.ps2up}`);
  switch (path.extname(args.output)) {
    case '.pdf':
      let pstopdf = cp.spawnSync('pstopdf', [args.ps2up, '-o', args.output]);
      if (pstopdf.status || pstopdf.error)
        throw `failed to generate postscript from ${args.input}`;
      break;
    default:
      throw `unexpected extension: ${path.extname(args.input)}`;
  }
}

async function print(args) {
  let ext = path.extname(args.input);
  let name = path.basename(args.input, ext);
  args.psfile = tmp.fileSync({dir: '.', prefix: name, postfix: '.ps'}).name;
  args.ps2up = tmp.fileSync({dir: '.', prefix: name, postfix: '.2up.ps'}).name;
  args.output = name + '.2up' + ext;
  debug(`arguments:`);
  debug(args);
  await convertToPostscript(args);
  await composePostscript(args);
  await convertFromPostscript(args);
  return args.output;
}
