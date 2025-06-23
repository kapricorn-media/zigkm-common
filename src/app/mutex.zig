const std = @import("std");

const platform = @import("zigkm-platform");

// Have to avoid threadlocal on Android because of https://github.com/ziglang/zig/issues/24236.
// std.Thread.Mutex uses threadlocal in Debug mode, so I gotta roll my own for now.
const AndroidMutex = struct {
    impl: FutexImpl = .{},

    pub fn lock(self: *@This()) void {
        self.impl.lock();
    }

    pub fn unlock(self: *@This()) void {
        self.impl.unlock();
    }
};

// Copy-pasted from Mutex.zig with some slight modifications.
const FutexImpl = struct {
    state: std.atomic.Value(u32) = std.atomic.Value(u32).init(unlocked),

    const unlocked: u32 = 0b00;
    const locked: u32 = 0b01;
    const contended: u32 = 0b11; // must contain the `locked` bit for x86 optimization below

    fn lock(self: *@This()) void {
        if (!self.tryLock())
            self.lockSlow();
    }

    fn tryLock(self: *@This()) bool {
        // Acquire barrier ensures grabbing the lock happens before the critical section
        // and that the previous lock holder's critical section happens before we grab the lock.
        return self.state.cmpxchgWeak(unlocked, locked, .acquire, .monotonic) == null;
    }

    fn lockSlow(self: *@This()) void {
        @setCold(true);

        // Avoid doing an atomic swap below if we already know the state is contended.
        // An atomic swap unconditionally stores which marks the cache-line as modified unnecessarily.
        if (self.state.load(.monotonic) == contended) {
            std.Thread.Futex.wait(&self.state, contended);
        }

        // Try to acquire the lock while also telling the existing lock holder that there are threads waiting.
        //
        // Once we sleep on the Futex, we must acquire the mutex using `contended` rather than `locked`.
        // If not, threads sleeping on the Futex wouldn't see the state change in unlock and potentially deadlock.
        // The downside is that the last mutex unlocker will see `contended` and do an unnecessary Futex wake
        // but this is better than having to wake all waiting threads on mutex unlock.
        //
        // Acquire barrier ensures grabbing the lock happens before the critical section
        // and that the previous lock holder's critical section happens before we grab the lock.
        while (self.state.swap(contended, .acquire) != unlocked) {
            std.Thread.Futex.wait(&self.state, contended);
        }
    }

    fn unlock(self: *@This()) void {
        // Unlock the mutex and wake up a waiting thread if any.
        //
        // A waiting thread will acquire with `contended` instead of `locked`
        // which ensures that it wakes up another thread on the next unlock().
        //
        // Release barrier ensures the critical section happens before we let go of the lock
        // and that our critical section happens before the next lock holder grabs the lock.
        const state = self.state.swap(unlocked, .release);
        std.debug.assert(state != unlocked);

        if (state == contended) {
            std.Thread.Futex.wake(&self.state, 1);
        }
    }
};

pub const Mutex = switch (platform.platform) {
    .android => AndroidMutex,
    else => std.Thread.Mutex,
};
