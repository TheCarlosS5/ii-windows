// R03: the lock contract as a state machine (quickshell/src/win32/compat/lockstate.hpp).
// Console test, no Qt and no Windows lock involved: it feeds the machine the events Windows would
// (call result, WTS lock/unlock, timeout, other sessions) in the orders that matter and checks
// the one invariant everything else hangs on: `secure` is true only after Windows said "locked".
#include <cstdio>
#include <cstdlib>
#include <string>

#include "../../quickshell/src/win32/compat/lockstate.hpp"

using qs::win32::compat::LockStateMachine;
using State = LockStateMachine::State;
using Event = LockStateMachine::SessionEvent;

namespace {
int checks = 0;
int failures = 0;

void check(bool ok, const char* what) {
	++checks;
	if (!ok) {
		++failures;
		std::printf("FAIL: %s\n", what);
	}
}
} // namespace

int main() {
	// 1. Nothing is known at first, and nothing is claimed.
	{
		LockStateMachine m;
		check(m.state() == State::Unknown && !m.secure() && !m.requested(), "new machine: unknown, not secure, not requested");
		m.init(State::Unknown);
		check(!m.secure(), "an unreadable session is not assumed locked");
		m.init(State::Unlocked);
		check(m.state() == State::Unlocked && !m.secure(), "observed unlocked");
	}

	// 2. A requested lock is secure only once Windows confirms it.
	{
		LockStateMachine m;
		m.init(State::Unlocked);
		auto e = m.requestLock();
		check(e.callLock && e.generation == 1, "requesting a lock asks for the call, at once (no animation delay)");
		check(m.state() == State::Requested && !m.secure(), "requested: not secure");
		check(m.requested(), "the shell's locked presentation is wanted");
		auto again = m.requestLock();
		check(!again.callLock, "asking twice does not call twice");
		auto r = m.lockCallResult(e.generation, true, 0, "");
		check(m.state() == State::Accepted && !m.secure(), "call accepted: still NOT secure (the lock is asynchronous)");
		check(r.armConfirm, "waiting for Windows' confirmation is bounded by a timeout");
		auto c = m.sessionEvent(Event::Lock, true);
		check(m.state() == State::Locked && m.secure(), "WTS lock event: now secure");
		check(c.lockedConfirmed && c.secureChanged && c.cancelConfirm, "confirmation is reported and the timeout cancelled");
		auto u = m.sessionEvent(Event::Unlock, true);
		check(m.state() == State::Unlocked && !m.secure() && !m.requested(), "WTS unlock event: unlocked, request cleared");
		check(u.unlockedConfirmed && !u.callLock, "unlocking never starts another lock request");
	}

	// 3. The call fails: error, no false protection, the presentation is withdrawn.
	{
		LockStateMachine m;
		m.init(State::Unlocked);
		auto e = m.requestLock();
		auto f = m.lockCallResult(e.generation, false, 5, "Access is denied.");
		check(m.state() == State::Error && !m.secure() && !m.requested(), "LockWorkStation failure: error, not secure, request cleared");
		check(f.failed && f.error.find("5") != std::string::npos && f.error.find("denied") != std::string::npos, "the failure carries the code and text");
		check(m.lastError() == f.error, "and stays readable");
		// A later request starts clean.
		auto retry = m.requestLock();
		check(retry.callLock && retry.generation == 2 && m.lastError().empty(), "a new request after an error starts fresh");
	}

	// 4. Accepted but Windows never confirms.
	{
		LockStateMachine m;
		m.init(State::Unlocked);
		auto e = m.requestLock();
		m.lockCallResult(e.generation, true, 0, "");
		auto t = m.confirmTimeout(e.generation);
		check(t.failed && m.state() == State::Error && !m.secure(), "no confirmation in time: error, not secure");
		// If Windows does lock later, that is the truth.
		auto late = m.sessionEvent(Event::Lock, true);
		check(m.secure() && late.lockedConfirmed, "a late real lock event still wins");
	}

	// 5. Stale timers and results are ignored.
	{
		LockStateMachine m;
		m.init(State::Unlocked);
		auto first = m.requestLock();
		m.lockCallResult(first.generation, true, 0, "");
		m.sessionEvent(Event::Lock, true);
		m.sessionEvent(Event::Unlock, true);
		auto stale = m.confirmTimeout(first.generation);
		check(!stale.failed && m.state() == State::Unlocked, "a timeout from before the unlock does nothing after it");
		auto staleResult = m.lockCallResult(first.generation, false, 5, "late");
		check(!staleResult.failed && m.state() == State::Unlocked, "a late call result from an old request does nothing");
	}

	// 6. Events of another session change nothing.
	{
		LockStateMachine m;
		m.init(State::Unlocked);
		auto e = m.sessionEvent(Event::Lock, false);
		check(m.state() == State::Unlocked && !m.secure() && !e.lockedConfirmed, "another session's lock event is ignored");
		m.sessionEvent(Event::Lock, true);
		auto o = m.sessionEvent(Event::Unlock, false);
		check(m.secure() && !o.unlockedConfirmed, "another session's unlock event does not unlock this one");
	}

	// 7. The shell can never unlock Windows.
	{
		LockStateMachine m;
		m.init(State::Unlocked);
		m.sessionEvent(Event::Lock, true);
		auto q = m.qmlUnlock();
		check(m.secure() && m.state() == State::Locked && !q.requestedChanged, "QML 'unlock' while Windows is locked changes nothing");
		LockStateMachine n;
		n.init(State::Unlocked);
		auto e = n.requestLock();
		n.lockCallResult(e.generation, true, 0, "");
		n.qmlUnlock();
		check(n.state() == State::Accepted && n.requested(), "QML cancelling after the lock call was accepted does not pretend to undo it");
		LockStateMachine idle;
		idle.init(State::Unlocked);
		idle.qmlUnlock();
		check(idle.state() == State::Unlocked, "QML 'unlock' while unlocked is a no-op");
	}

	// 8. Win+L (or idle, lid) without any request from the shell.
	{
		LockStateMachine m;
		m.init(State::Unlocked);
		auto e = m.sessionEvent(Event::Lock, true);
		check(m.secure() && m.requested() && e.lockedConfirmed && !e.callLock, "a Windows-initiated lock makes the shell show its locked state without calling the API");
		auto dup = m.sessionEvent(Event::Lock, true);
		check(!dup.lockedConfirmed, "a repeated lock event is not reported twice");
	}

	// 9. Started while Windows is already locked.
	{
		LockStateMachine m;
		m.init(State::Locked);
		check(m.secure() && m.requested(), "starting inside a locked session: secure and presenting locked");
		auto r = m.requestLock();
		check(!r.callLock, "no second lock is requested over a locked session");
	}

	// 10. Resync after a reconnect.
	{
		LockStateMachine m;
		m.init(State::Unlocked);
		auto e = m.resync(State::Locked);
		check(m.secure() && e.lockedConfirmed, "a reconnect that finds the session locked follows it");
		auto u = m.resync(State::Unlocked);
		check(!m.secure() && u.unlockedConfirmed, "and follows the unlock");
		auto none = m.resync(State::Unknown);
		check(!none.stateChanged && m.state() == State::Unlocked, "an unreadable reading moves nothing");
	}

	std::printf("lockstate: %d checks, %d failed\n", checks, failures);
	return failures == 0 ? 0 : 1;
}
