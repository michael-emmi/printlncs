import assert from 'assert';
import child_process from 'child_process';
import fs from 'fs';
import util from 'util';

const exec = util.promisify(child_process.exec);
const command = 'bin/cli.js';
const documents = 'resources';

describe('The printlncs CLI', () => {
  for (const document of fs.readdirSync(documents)) {
    it(`should work on the sample document ${document}`, async () => {

        try {
          const { stdout, stderr } = await exec(`${command} ${documents}/${document}`);

        } catch (error) {
          assert.fail(error);
        }
      });
  }
});
