import { db, BreadcrumbRecord } from '../../../shared/src/database/db';

export interface WriteBehindQueueOptions {
  batchSize?: number;
  flushIntervalMs?: number;
  maxQueueSize?: number;
}

export class WriteBehindQueue {
  private buffer: BreadcrumbRecord[] = [];
  private timer: NodeJS.Timeout | null = null;
  private isFlushing = false;
  private isStopped = false;
  private readonly batchSize: number;
  private readonly flushIntervalMs: number;
  private readonly maxQueueSize: number;

  constructor(options: WriteBehindQueueOptions = {}) {
    this.batchSize = options.batchSize || 100;
    this.flushIntervalMs = options.flushIntervalMs || 1000;
    this.maxQueueSize = options.maxQueueSize || 10000;
  }

  public start(): void {
    if (this.timer) return;
    this.isStopped = false;

    this.timer = setInterval(() => {
      this.flushBatch().catch((err) => {
        console.error('[WriteBehindQueue Interval Flush Error]:', err);
      });
    }, this.flushIntervalMs);

    if (this.timer.unref) {
      this.timer.unref();
    }
  }

  public enqueue(record: BreadcrumbRecord): boolean {
    if (this.isStopped) {
      return false;
    }

    if (this.buffer.length >= this.maxQueueSize) {
      console.warn(
        `[WriteBehindQueue] Max queue capacity (${this.maxQueueSize}) reached. Dropping oldest breadcrumb to prevent memory pressure.`
      );
      this.buffer.shift();
    }

    this.buffer.push(record);

    if (this.buffer.length >= this.batchSize) {
      setImmediate(() => {
        this.flushBatch().catch((err) => {
          console.error('[WriteBehindQueue Batch Trigger Error]:', err);
        });
      });
    }

    return true;
  }

  public async flushBatch(): Promise<number> {
    if (this.isFlushing || this.buffer.length === 0) {
      return 0;
    }

    this.isFlushing = true;
    const batch = this.buffer.splice(0, this.batchSize);

    try {
      await db.insertBreadcrumbsBatch(batch);
      return batch.length;
    } catch (err: any) {
      console.error(`[WriteBehindQueue DB Persist Error - Retaining ${batch.length} items]:`, err.message);
      // If error is foreign key violation (e.g. user deleted or database truncated), drop batch
      if (err.code === '23503') {
        console.warn('[WriteBehindQueue] Foreign key violation: dropping orphaned breadcrumb batch.');
        return 0;
      }
      // Put items back at the head of the buffer if queue has capacity
      if (this.buffer.length + batch.length <= this.maxQueueSize) {
        this.buffer.unshift(...batch);
      }
      throw err;
    } finally {
      this.isFlushing = false;
    }
  }

  public async flush(): Promise<void> {
    const maxAttempts = 10;
    let attempts = 0;
    while (this.buffer.length > 0 && attempts < maxAttempts) {
      attempts++;
      try {
        await this.flushBatch();
      } catch (err) {
        break;
      }
    }
  }

  public clear(): void {
    this.buffer = [];
  }

  public async flushAndStop(): Promise<void> {
    this.isStopped = true;
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    await this.flush();
  }

  public getQueueLength(): number {
    return this.buffer.length;
  }
}