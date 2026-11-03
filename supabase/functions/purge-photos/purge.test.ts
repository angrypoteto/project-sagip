// Run with: node --test supabase/functions/purge-photos/purge.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { type ExpiredFile, purgeExpired } from "./purge.ts";

function fakeStore(n: number, failOnBatch = -1) {
  const expired: ExpiredFile[] = Array.from({ length: n }, (_, i) => ({
    photo_id: `p${i}`,
    storage_path: `user/p${i}.jpg`,
  }));
  const deleted: string[] = [];
  let removeCalls = 0;
  return {
    deleted,
    left: () => expired.length,
    deps: {
      list: async (limit: number) => expired.slice(0, limit),
      remove: async (paths: string[]) => {
        if (removeCalls++ === failOnBatch) throw new Error("storage: HTTP 500");
        deleted.push(...paths);
      },
      mark: async (ids: string[]) => {
        for (const id of ids) {
          const i = expired.findIndex((f) => f.photo_id === id);
          if (i >= 0) expired.splice(i, 1);
        }
        return ids.length;
      },
    },
  };
}

test("deletes every expired file in batches, then marks them", async () => {
  const s = fakeStore(250);
  const r = await purgeExpired(s.deps, 100);
  assert.deepEqual(r, { removed: 250, batches: 3 });
  assert.equal(s.deleted.length, 250);
  assert.equal(s.left(), 0);
});

test("nothing expired: no delete call", async () => {
  const s = fakeStore(0);
  assert.deepEqual(await purgeExpired(s.deps), { removed: 0, batches: 0 });
  assert.equal(s.deleted.length, 0);
});

test("a failed delete marks nothing, so the next run tries again", async () => {
  const s = fakeStore(150, 1);
  await assert.rejects(purgeExpired(s.deps, 100), /HTTP 500/);
  assert.equal(s.left(), 50, "the first batch went; the failed one is still waiting");
});

test("stops after maxBatches; the rest waits for the next run", async () => {
  const s = fakeStore(500);
  const r = await purgeExpired(s.deps, 100, 2);
  assert.deepEqual(r, { removed: 200, batches: 2 });
  assert.equal(s.left(), 300);
});
