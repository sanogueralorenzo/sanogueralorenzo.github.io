#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { createHash, createPrivateKey, createPublicKey } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const JURY_NOW = "2026-05-23T00:00:00.000Z";
const KEY_ID = "ci-fixture";
const CLAIM_ID = "claim_ci_change";
const KEY_SEED = "jury-key-policy-fixture-v1";
const ROTATION_OLD_KEY_ID = "ci-old";
const ROTATION_NEW_KEY_ID = "ci-new";
const scriptDir = dirname(fileURLToPath(import.meta.url));
const juryRoot = dirname(scriptDir);
const repoRoot = dirname(juryRoot);
const cliPath = join(juryRoot, "bin/jury.mjs");
const fixtureDir = join(juryRoot, "examples/ci/fixtures/key-policy");
const rotationFixtureDir = join(juryRoot, "examples/ci/fixtures/key-policy-rotation");
const checkOnly = process.argv.includes("--check");

const tmp = mkdtempSync(join(tmpdir(), "jury-key-policy-fixtures-"));
const outDir = checkOnly ? join(tmp, "fixtures") : fixtureDir;
const rotationOutDir = checkOnly ? join(tmp, "fixtures-rotation") : rotationFixtureDir;
const stateDir = join(tmp, ".jury");
const privateKeyPath = join(tmp, "ci-private.pem");
const rotationOldPrivateKeyPath = join(tmp, "ci-old-private.pem");
const rotationNewPrivateKeyPath = join(tmp, "ci-new-private.pem");

try {
  const keyPair = createFixtureKeyPair(KEY_SEED);
  const rotationOldKeyPair = createFixtureKeyPair("jury-key-policy-rotation-old-v1");
  const rotationNewKeyPair = createFixtureKeyPair("jury-key-policy-rotation-new-v1");

  mkdirSync(outDir, { recursive: true });
  mkdirSync(rotationOutDir, { recursive: true });
  writeFileSync(privateKeyPath, keyPair.privateKey);
  writeFileSync(join(outDir, "ci-public.pem"), keyPair.publicKey);
  writeFileSync(join(outDir, "jury-key-policy.json"), `${JSON.stringify(keyPolicy(), null, 2)}\n`);
  writeFileSync(rotationOldPrivateKeyPath, rotationOldKeyPair.privateKey);
  writeFileSync(rotationNewPrivateKeyPath, rotationNewKeyPair.privateKey);
  writeFileSync(join(rotationOutDir, "ci-old-public.pem"), rotationOldKeyPair.publicKey);
  writeFileSync(join(rotationOutDir, "ci-new-public.pem"), rotationNewKeyPair.publicKey);
  writeFileSync(join(rotationOutDir, "jury-key-policy.rotation.json"), `${JSON.stringify(rotationKeyPolicy(), null, 2)}\n`);
  writeFileSync(join(rotationOutDir, "jury-key-policy.revoked-old.json"), `${JSON.stringify(revokedOldKeyPolicy(), null, 2)}\n`);

  buildAcceptedReviewState(stateDir);
  runJury([
    "bundle", "export",
    "--state-dir", stateDir,
    "--claim", CLAIM_ID,
    "--out", join(outDir, "review-bundle.signed.json"),
    "--attest-private-key", privateKeyPath,
    "--attestation-key-id", KEY_ID,
    "--source", "local",
    "--revision", "unknown",
  ]);
  runJury(["bundle", "preflight", "--bundle", join(outDir, "review-bundle.signed.json"), "--key-policy", join(outDir, "jury-key-policy.json")]);
  runJury([
    "bundle", "export",
    "--state-dir", stateDir,
    "--claim", CLAIM_ID,
    "--out", join(rotationOutDir, "review-bundle.old.signed.json"),
    "--attest-private-key", rotationOldPrivateKeyPath,
    "--attestation-key-id", ROTATION_OLD_KEY_ID,
    "--source", "local",
    "--revision", "unknown",
  ]);
  runJury([
    "bundle", "export",
    "--state-dir", stateDir,
    "--claim", CLAIM_ID,
    "--out", join(rotationOutDir, "review-bundle.new.signed.json"),
    "--attest-private-key", rotationNewPrivateKeyPath,
    "--attestation-key-id", ROTATION_NEW_KEY_ID,
    "--source", "local",
    "--revision", "unknown",
  ]);
  runJury(["bundle", "preflight", "--bundle", join(rotationOutDir, "review-bundle.old.signed.json"), "--key-policy", join(rotationOutDir, "jury-key-policy.rotation.json")]);
  runJury(["bundle", "preflight", "--bundle", join(rotationOutDir, "review-bundle.new.signed.json"), "--key-policy", join(rotationOutDir, "jury-key-policy.rotation.json")]);
  runJury(["bundle", "preflight", "--bundle", join(rotationOutDir, "review-bundle.new.signed.json"), "--key-policy", join(rotationOutDir, "jury-key-policy.revoked-old.json")]);
  runJuryExpectFailure(["bundle", "preflight", "--bundle", join(rotationOutDir, "review-bundle.old.signed.json"), "--key-policy", join(rotationOutDir, "jury-key-policy.revoked-old.json")], "revoked");

  if (checkOnly) {
    const hasDrift = [
      assertFixtureDrift("ci-public.pem", outDir),
      assertFixtureDrift("jury-key-policy.json", outDir),
      assertFixtureDrift("review-bundle.signed.json", outDir),
      assertFixtureDrift("ci-old-public.pem", rotationOutDir, rotationFixtureDir),
      assertFixtureDrift("ci-new-public.pem", rotationOutDir, rotationFixtureDir),
      assertFixtureDrift("jury-key-policy.rotation.json", rotationOutDir, rotationFixtureDir),
      assertFixtureDrift("jury-key-policy.revoked-old.json", rotationOutDir, rotationFixtureDir),
      assertFixtureDrift("review-bundle.old.signed.json", rotationOutDir, rotationFixtureDir),
      assertFixtureDrift("review-bundle.new.signed.json", rotationOutDir, rotationFixtureDir),
    ].some(Boolean);

    if (hasDrift) {
      process.exitCode = 1;
    } else {
      process.stdout.write("key-policy fixtures are in sync\n");
    }
  } else {
    process.stdout.write("generated key-policy fixtures\n");
  }
} finally {
  rmSync(tmp, { recursive: true, force: true });
}

function keyPolicy() {
  return {
    schema_version: "jury.key_policy.v1",
    producers: [{
      name: "@sanogueralorenzo/jury",
      version: "0.1.0",
      source: "local",
      revision_pattern: "^unknown$",
      keys: [{
        key_id: KEY_ID,
        type: "rsa-sha256",
        public_key_path: "ci-public.pem",
        valid_from: "2026-05-22T00:00:00.000Z",
        valid_until: "2026-05-24T00:00:00.000Z",
      }],
    }],
  };
}

function rotationKeyPolicy() {
  return {
    schema_version: "jury.key_policy.v1",
    producers: [{
      name: "@sanogueralorenzo/jury",
      version: "0.1.0",
      source: "local",
      revision_pattern: "^unknown$",
      keys: [
        {
          key_id: ROTATION_OLD_KEY_ID,
          type: "rsa-sha256",
          public_key_path: "ci-old-public.pem",
          valid_from: "2026-05-01T00:00:00.000Z",
          valid_until: "2026-06-01T00:00:00.000Z",
        },
        {
          key_id: ROTATION_NEW_KEY_ID,
          type: "rsa-sha256",
          public_key_path: "ci-new-public.pem",
          valid_from: "2026-05-15T00:00:00.000Z",
          valid_until: "2026-07-01T00:00:00.000Z",
        },
      ],
    }],
  };
}

function revokedOldKeyPolicy() {
  return {
    schema_version: "jury.key_policy.v1",
    producers: [{
      name: "@sanogueralorenzo/jury",
      version: "0.1.0",
      source: "local",
      revision_pattern: "^unknown$",
      keys: [
        {
          key_id: ROTATION_OLD_KEY_ID,
          type: "rsa-sha256",
          public_key_path: "ci-old-public.pem",
          valid_from: "2026-05-01T00:00:00.000Z",
          valid_until: "2026-06-01T00:00:00.000Z",
          revoked_at: "2026-06-01T00:00:00.000Z",
          revoked_reason: "migration window closed; ci-new is the active producer key",
        },
        {
          key_id: ROTATION_NEW_KEY_ID,
          type: "rsa-sha256",
          public_key_path: "ci-new-public.pem",
          valid_from: "2026-05-15T00:00:00.000Z",
          valid_until: "2026-07-01T00:00:00.000Z",
        },
      ],
    }],
  };
}

function buildAcceptedReviewState(targetStateDir) {
  runJury(["init", "--state-dir", targetStateDir]);
  runJury(["claim", "create", "--state-dir", targetStateDir, "--id", CLAIM_ID, "--summary", "pull request is ready", "--scope", "jury", "--impact", "high"]);
  runJury(["claim", "transition", "--state-dir", targetStateDir, "--claim", CLAIM_ID, "--status", "screening"]);
  runJury(["claim", "transition", "--state-dir", targetStateDir, "--claim", CLAIM_ID, "--status", "in_review"]);
  runJury(["check", "add", "--state-dir", targetStateDir, "--id", "check_ci_tests", "--claim", CLAIM_ID, "--type", "verifier", "--summary", "Jury tests must pass"]);
  runJury(["evidence", "add", "--state-dir", targetStateDir, "--id", "ev_ci_tests", "--claim", CLAIM_ID, "--type", "command", "--command", "npm --prefix jury test", "--exit-code", "0"]);
  runJury(["critic", "run", "--state-dir", targetStateDir, "--claim", CLAIM_ID, "--role", "tests"]);
  runJury(["critic", "run", "--state-dir", targetStateDir, "--claim", CLAIM_ID, "--role", "security"]);
  runJury(["critic", "run", "--state-dir", targetStateDir, "--claim", CLAIM_ID, "--role", "scope", "--changed-files", "jury/bin/jury.mjs,jury/test/jury.test.mjs"]);
  runJury(["check", "update", "--state-dir", targetStateDir, "--id", "check_ci_tests", "--status", "passed", "--evidence", "ev_ci_tests", "--resolution", "Jury tests passed"]);
  runJury(["judge", "--state-dir", targetStateDir, "--claim", CLAIM_ID, "--out", join(tmp, "verdict.json")]);
  runJury(["gate", "--state-dir", targetStateDir, "--claim", CLAIM_ID, "--verdict", join(tmp, "verdict.json")]);
}

function runJury(args) {
  const env = { ...process.env, JURY_NOW };
  delete env.GITHUB_REPOSITORY;
  delete env.GITHUB_SHA;
  delete env.GITHUB_WORKFLOW;
  delete env.GITHUB_RUN_ID;

  const result = spawnSync(process.execPath, [cliPath, ...args, "--json"], {
    cwd: repoRoot,
    env,
    encoding: "utf8",
  });

  if (result.status !== 0) {
    throw new Error(`jury ${args.join(" ")} failed\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
  }

  return result.stdout;
}

function runJuryExpectFailure(args, expectedMessage) {
  const env = { ...process.env, JURY_NOW };
  delete env.GITHUB_REPOSITORY;
  delete env.GITHUB_SHA;
  delete env.GITHUB_WORKFLOW;
  delete env.GITHUB_RUN_ID;

  const result = spawnSync(process.execPath, [cliPath, ...args, "--json"], {
    cwd: repoRoot,
    env,
    encoding: "utf8",
  });

  if (result.status === 0 || !result.stdout.includes(expectedMessage)) {
    throw new Error(`jury ${args.join(" ")} expected failure containing ${expectedMessage}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
  }
}

function assertFixtureDrift(filename, generatedDir, expectedDir = fixtureDir) {
  const expectedPath = join(expectedDir, filename);
  const generatedPath = join(generatedDir, filename);
  const expected = readFileSync(expectedPath, "utf8");
  const generated = readFileSync(generatedPath, "utf8");

  if (expected !== generated) {
    process.stderr.write(`${filename} is out of date; run npm --prefix jury run fixtures:key-policy\n`);
    return true;
  }

  return false;
}

function createFixtureKeyPair(seed) {
  const e = 65537n;
  let p = deterministicPrime(`${seed}:p`);
  let q = deterministicPrime(`${seed}:q`);

  while (p === q || gcd((p - 1n) * (q - 1n), e) !== 1n) {
    q = deterministicPrime(`${seed}:q:${q}`);
  }

  if (p < q) {
    [p, q] = [q, p];
  }

  const n = p * q;
  const phi = (p - 1n) * (q - 1n);
  const d = modInverse(e, phi);
  const jwk = {
    kty: "RSA",
    n: base64Url(n),
    e: base64Url(e),
    d: base64Url(d),
    p: base64Url(p),
    q: base64Url(q),
    dp: base64Url(d % (p - 1n)),
    dq: base64Url(d % (q - 1n)),
    qi: base64Url(modInverse(q, p)),
  };
  const privateKey = createPrivateKey({ key: jwk, format: "jwk" });
  const publicKey = createPublicKey(privateKey);

  return {
    privateKey: privateKey.export({ format: "pem", type: "pkcs8" }),
    publicKey: publicKey.export({ format: "pem", type: "spki" }),
  };
}

function deterministicPrime(label) {
  for (let index = 0n; ; index += 1n) {
    const candidate = candidateInteger(label, index);

    if (isProbablePrime(candidate)) {
      return candidate;
    }
  }
}

function candidateInteger(label, index) {
  const bytes = Buffer.alloc(64);

  for (let offset = 0; offset < bytes.length; offset += 32) {
    const block = createHash("sha256").update(`${label}:${index}:${offset}`).digest();
    block.copy(bytes, offset);
  }

  bytes[0] |= 0x80;
  bytes[bytes.length - 1] |= 0x01;
  return BigInt(`0x${bytes.toString("hex")}`);
}

function isProbablePrime(value) {
  const smallPrimes = [3n, 5n, 7n, 11n, 13n, 17n, 19n, 23n, 29n, 31n, 37n, 41n];

  if (value < 2n) {
    return false;
  }

  for (const prime of smallPrimes) {
    if (value === prime) {
      return true;
    }

    if (value % prime === 0n) {
      return false;
    }
  }

  let d = value - 1n;
  let s = 0n;

  while (d % 2n === 0n) {
    d /= 2n;
    s += 1n;
  }

  for (const base of [2n, 3n, 5n, 7n, 11n, 13n, 17n, 19n, 23n, 29n, 31n, 37n]) {
    if (base >= value - 2n) {
      continue;
    }

    let x = modPow(base, d, value);

    if (x === 1n || x === value - 1n) {
      continue;
    }

    let witness = true;

    for (let r = 1n; r < s; r += 1n) {
      x = modPow(x, 2n, value);

      if (x === value - 1n) {
        witness = false;
        break;
      }
    }

    if (witness) {
      return false;
    }
  }

  return true;
}

function modPow(base, exponent, modulus) {
  let result = 1n;
  let factor = base % modulus;
  let remaining = exponent;

  while (remaining > 0n) {
    if (remaining % 2n === 1n) {
      result = (result * factor) % modulus;
    }

    factor = (factor * factor) % modulus;
    remaining /= 2n;
  }

  return result;
}

function gcd(a, b) {
  let x = a;
  let y = b;

  while (y !== 0n) {
    [x, y] = [y, x % y];
  }

  return x;
}

function modInverse(value, modulus) {
  let oldR = value;
  let r = modulus;
  let oldS = 1n;
  let s = 0n;

  while (r !== 0n) {
    const quotient = oldR / r;
    [oldR, r] = [r, oldR - quotient * r];
    [oldS, s] = [s, oldS - quotient * s];
  }

  if (oldR !== 1n) {
    throw new Error("value has no modular inverse");
  }

  return oldS < 0n ? oldS + modulus : oldS;
}

function base64Url(value) {
  let hex = value.toString(16);

  if (hex.length % 2 === 1) {
    hex = `0${hex}`;
  }

  return Buffer.from(hex, "hex").toString("base64url");
}
