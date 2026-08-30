import test from 'node:test';
import assert from 'node:assert/strict';
import { NodeProcessRunner } from './node-process-runner.ts';
import { defineProcessCommand } from './process-command.ts';
import { CommandRegistry } from './command-registry.ts';

test('silent process commands capture output without a terminal', async () => {
  const runner = new NodeProcessRunner();
  const registry = new CommandRegistry();
  registry.register(defineProcessCommand({
    id: 'tonal-local',
    title: 'Tonal Local',
    keywords: ['tonal'],
    command: process.execPath,
    args: ['-e', 'process.stdout.write("tonal ready")'],
  }, runner));

  const result = await registry.execute('tonal-local', {
    platform: 'macos',
    invocation: 'visible',
    signal: new AbortController().signal,
  });

  assert.equal(result.status, 'success');
  assert.equal(result.output, 'tonal ready');
});

test('failed processes return stderr and exit code', async () => {
  const result = await new NodeProcessRunner().run({
    command: process.execPath,
    args: ['-e', 'process.stderr.write("bad"); process.exit(3)'],
    background: true,
  });

  assert.equal(result.status, 'failure');
  assert.equal(result.exitCode, 3);
  assert.equal(result.message, 'bad');
});
