// The photo file cleanup (NFR4, 2026-11-03), apart from the server so
// Node can test it (purge.test.ts): ask for expired photo files in
// batches, delete each batch from the bucket, and mark those photos.

export interface ExpiredFile {
  photo_id: string;
  storage_path: string;
}

export interface PurgeDeps {
  /** `expired_photo_files(p_limit)`. */
  list(limit: number): Promise<ExpiredFile[]>;
  /** Deletes these paths from the incident-photos bucket. */
  remove(paths: string[]): Promise<void>;
  /** `mark_photo_files_removed(p_photo_ids)`: how many were marked. */
  mark(ids: string[]): Promise<number>;
}

/**
 * Deletes every expired photo file, [batch] at a time, at most [maxBatches]
 * batches per run (the next day's run takes the rest). A file already gone
 * from the bucket counts as deleted: the Storage API does not fail on it.
 * A failed delete stops the run with nothing marked for that batch, so
 * the next run tries those files again.
 */
export async function purgeExpired(
  deps: PurgeDeps,
  batch = 100,
  maxBatches = 20,
): Promise<{ removed: number; batches: number }> {
  let removed = 0;
  let batches = 0;
  while (batches < maxBatches) {
    const files = await deps.list(batch);
    if (files.length === 0) break;
    await deps.remove(files.map((f) => f.storage_path));
    removed += await deps.mark(files.map((f) => f.photo_id));
    batches++;
    if (files.length < batch) break;
  }
  return { removed, batches };
}
