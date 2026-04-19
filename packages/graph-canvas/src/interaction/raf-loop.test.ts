/**
 * @file RAF loop contract — the per-frame visibility recompute.
 *
 * Pins down that the loop drives BOTH the camera tick AND a
 * camera-dependent recompute every frame, not only render. Without
 * this contract, projected sizes / interior LOD only refresh when an
 * event handler manually calls update — leading to "frozen detail"
 * during camera tweens.
 */

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { startRafLoop } from "./raf-loop.ts";

type Frame = () => void;

/** Capture requestAnimationFrame so we can drive it manually. The
 *  global rAF normally schedules off-thread; in node we replace it
 *  with a queue and pump frames in the test. */
function installRaf(): {
  readonly tick: () => void;
  readonly pendingFrames: () => number;
  readonly restore: () => void;
} {
  const queue: Frame[] = [];
  const original = globalThis.requestAnimationFrame;
  const originalCancel = globalThis.cancelAnimationFrame;
  let nextId = 1;
  const pending = new Map<number, Frame>();
  globalThis.requestAnimationFrame = ((cb: Frame): number => {
    const id = nextId++;
    pending.set(id, cb);
    queue.push(() => {
      pending.delete(id);
      cb();
    });
    return id;
  }) as typeof requestAnimationFrame;
  globalThis.cancelAnimationFrame = ((id: number): void => {
    pending.delete(id);
  }) as typeof cancelAnimationFrame;
  return {
    tick: () => {
      const frame = queue.shift();
      if (frame) {
        frame();
      }
    },
    pendingFrames: () => queue.length,
    restore: () => {
      globalThis.requestAnimationFrame = original;
      globalThis.cancelAnimationFrame = originalCancel;
    },
  };
}

type FakeRenderer = {
  readonly tickControls: ReturnType<typeof vi.fn>;
  readonly recomputeFrame: ReturnType<typeof vi.fn>;
  readonly render: ReturnType<typeof vi.fn>;
  readonly getCameraSignature: ReturnType<typeof vi.fn>;
  readonly hasActiveTween: ReturnType<typeof vi.fn>;
};

function fakeRenderer(): FakeRenderer {
  let signature = "0,0,0|0,0,0";
  return {
    tickControls: vi.fn(() => {
      // Each tick advances the camera signature so the loop sees motion
      // and keeps spinning.
      signature = `${Math.random()},0,0|0,0,0`;
    }),
    recomputeFrame: vi.fn(),
    render: vi.fn(),
    getCameraSignature: vi.fn(() => signature),
    hasActiveTween: vi.fn(() => false),
  };
}

describe("startRafLoop", () => {
  let raf: ReturnType<typeof installRaf>;

  beforeEach(() => {
    raf = installRaf();
  });

  afterEach(() => {
    raf.restore();
  });

  it("calls recomputeFrame and render every tick", () => {
    // Camera-dependent visibility (LOD, projected sizes) must be
    // re-evaluated every frame the loop runs. Without this, detail
    // freezes between user events.
    const renderer = fakeRenderer();
    const ref = { current: renderer as unknown as Parameters<typeof startRafLoop>[0]["current"] };
    const handle = startRafLoop(ref);
    // Initial kick scheduled the first frame.
    raf.tick();
    expect(renderer.recomputeFrame).toHaveBeenCalledTimes(1);
    expect(renderer.render).toHaveBeenCalledTimes(1);
    raf.tick();
    expect(renderer.recomputeFrame).toHaveBeenCalledTimes(2);
    expect(renderer.render).toHaveBeenCalledTimes(2);
    handle.stop();
  });

  it("parks itself after a stable camera and resumes on kick", () => {
    // Stable camera + no tween → loop stops requesting frames.
    // A subsequent kick must restart it.
    const renderer = fakeRenderer();
    // Override tickControls so the camera signature stays stable.
    renderer.tickControls.mockImplementation(() => {});
    const ref = { current: renderer as unknown as Parameters<typeof startRafLoop>[0]["current"] };
    const handle = startRafLoop(ref);
    // Pump enough frames for the quiet-counter to trip.
    for (let i = 0; i < 8; i++) {
      raf.tick();
    }
    const beforeKickPending = raf.pendingFrames();
    expect(beforeKickPending).toBe(0);
    const recomputeBefore = renderer.recomputeFrame.mock.calls.length;
    handle.kick();
    raf.tick();
    expect(renderer.recomputeFrame.mock.calls.length).toBe(recomputeBefore + 1);
    handle.stop();
  });

  it("does not call renderer methods after stop", () => {
    const renderer = fakeRenderer();
    const ref = { current: renderer as unknown as Parameters<typeof startRafLoop>[0]["current"] };
    const handle = startRafLoop(ref);
    handle.stop();
    raf.tick();
    expect(renderer.recomputeFrame).not.toHaveBeenCalled();
    expect(renderer.render).not.toHaveBeenCalled();
  });
});
